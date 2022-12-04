//
//  CBLNWWebSocket.mm
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLNWWebSocket.h"

#import "CBLCoreBridge.h"
#import "CBLHTTPLogic.h"
#import "CBLStatus.h"
#import "CBLTrustCheck.h"

#import "CBLReplicatorConfiguration.h"  // for the options constants
#import "CBLReplicator+Internal.h"
#import "CBLDatabase+Internal.h"

#import "MYURLUtils.h"

#import "c4Socket.h"
#import "fleece/Fleece.hh"

#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#import <Network/Network.h>

#ifdef COUCHBASE_ENTERPRISE
#import "CBLCert.h"
#endif

using namespace fleece;

// Number of bytes to read from the socket at a time
static constexpr size_t kReadBufferSize = 32 * 1024;

// Max number of bytes read that haven't been processed by LiteCore yet.
// Beyond this point, I will stop reading from the socket, sending backpressure to the peer.
static constexpr size_t kMaxReceivedBytesPending = 100 * 1024;

/** For resolving the network interface name to the nw_interface_t object. */
@interface CBLInterfaceResolver : NSObject

- (instancetype) initWithInterface: (NSString*)name
                             queue: (dispatch_queue_t)queue
                        completion: (void (^)(CBLInterfaceResolver* resolver,
                                              nw_interface_t _Nullable interface))completion NW_API_AVAILABLE;

- (void) cancel;

@end

@interface CBLNWWebSocket ()

- (instancetype) initWithURL: (NSURL*)url
                    c4socket: (C4Socket*)c4socket
                     options: (slice)options
                     context: (void*)context;

- (void) start;

@end

@implementation CBLNWWebSocket {
    id _keepMeAlive;
    
    dispatch_queue_t _queue;
    
    std::atomic<C4Socket*> _c4socket;
    AllocedDict _options;
    NSURL* _remoteURL;
    
    nw_connection_t _connection;                    // Connection object
    NSMutableSet* _disconnectingConnections;        // Keeping connections alive until completely cancelled
    NSCondition* _disposeCondition;                 // To ensure that connections are all cancelled
    
    // Network Interface:
    NSString* _networkInterface;
    CBLInterfaceResolver* _interfaceResolver;
    nw_interface_t _nwInterface;
    
    // HTTP and WebSocket:
    CBLHTTPLogic* _logic;
    NSString* _expectedAcceptHeader;
    CFHTTPMessageRef _httpResponse;
    size_t _receivedBytesPending;
#ifdef COUCHBASE_ENTERPRISE
    // Client Cert Authentication:
    NSArray* _clientIdentity;
#endif
    
    // Flags:
    bool _gotResponseHeaders;
    BOOL _connectingToProxy;
    BOOL _connectedThruProxy;
    BOOL _closing;
    
    // Replicator an database:
    CBLReplicator* _replicator;                     // For getting the replicator config
    CBLDatabase* _db;                               // For saving cookies
}

+ (C4SocketFactory) socketFactory {
    return {
        .framing = kC4WebSocketClientFraming,
        .open = &doOpen,
        .close = &doClose,
        .write = &doWrite,
        .completedReceive = &doCompletedReceive,
        .dispose = &doDispose,
    };
}

static void doOpen(C4Socket* s, const C4Address* addr, C4Slice optionsFleece, void* context) {
    @autoreleasepool {
        NSURLComponents* c = [NSURLComponents new];
        if (addr->scheme == "blips"_sl || addr->scheme == "wss"_sl)
            c.scheme = @"https";
        else if (addr->scheme == "blip"_sl || addr->scheme == "ws"_sl)
            c.scheme = @"http";
        else {
            c4socket_closed(s, {LiteCoreDomain, kC4NetErrInvalidURL});
            return;
        }
        c.host = slice2string(addr->hostname);
        c.port = @(addr->port);
        c.path = slice2string(addr->path);
        NSURL* url = c.URL;
        if (!url) {
            c4socket_closed(s, {LiteCoreDomain, kC4NetErrInvalidURL});
            return;
        }
        auto socket = [[CBLNWWebSocket alloc] initWithURL: url
                                                 c4socket: s
                                                  options: optionsFleece
                                                  context: context];
        c4Socket_setNativeHandle(s, (__bridge void*)socket);
        socket->_keepMeAlive = socket;          // Prevents dealloc until doDispose is called
        [socket start];
    }
}

static CBLNWWebSocket* getWebSocket(C4Socket *s) {
    return (__bridge CBLNWWebSocket*)c4Socket_getNativeHandle(s);
}

static void doClose(C4Socket* s) {
    IF_NW_API_AVAILABLE {
        [getWebSocket(s) closeSocket];
    }
}

static void doWrite(C4Socket* s, C4SliceResult allocatedData) {
    IF_NW_API_AVAILABLE {
        [getWebSocket(s) writeAndFree: allocatedData];
    }
}

static void doCompletedReceive(C4Socket* s, size_t byteCount) {
    IF_NW_API_AVAILABLE {
        [getWebSocket(s) completedReceive: byteCount];
    }
}

static void doDispose(C4Socket* s) {
    [getWebSocket(s) dispose];
}

- (instancetype) initWithURL: (NSURL*)url
                    c4socket: (C4Socket*)c4socket
                     options: (slice)options
                     context: (void*)context {
    self = [super init];
    if (self) {
        _c4socket = c4socket;
        _options = AllocedDict(options);
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        _replicator = (__bridge CBLReplicator*)context;
        _db = _replicator.config.database;
        _networkInterface = _replicator.config.networkInterface;
#pragma clang diagnostic pop
        
        _remoteURL = url;
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url];
        request.HTTPShouldHandleCookies = NO;
        _logic = [[CBLHTTPLogic alloc] initWithURLRequest: request];
        _logic.handleRedirects = YES;
        [self setupAuth];
        
        _disconnectingConnections = [NSMutableSet set];
        _disposeCondition = [[NSCondition alloc] init];

        NSString* queueName = [NSString stringWithFormat: @"NWWebSocket-%@:%u", url.host, _logic.port];
        _queue = dispatch_queue_create(queueName.UTF8String, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void) dealloc {
    CBLLogVerbose(WebSocket, @"DEALLOC %@", self);
    if (_httpResponse)
        CFRelease(_httpResponse);
}

- (void) dispose {
    CBLLogVerbose(WebSocket, @"%@: C4Socket is being disposed ...", self);
    // This has to be done synchronously, because _c4socket will be freed when this method returns
    auto socket = _c4socket.exchange(nullptr);
    if (socket)
        c4Socket_setNativeHandle(socket, nullptr);
    
    [_disposeCondition lock];
    while (_disconnectingConnections.count > 0) {
        CBLLogVerbose(WebSocket, @"%@: Waiting for %lu connection(s) to be cancelled ...",
                      self, (unsigned long)_disconnectingConnections);
        [_disposeCondition wait];
    }
    [_disposeCondition unlock];
    
    // Remove the self-reference, so this object will be dealloced:
    CBLLogVerbose(WebSocket, @"%@: C4Socket is now disposed", self);
    _keepMeAlive = nil;
}

- (void) callC4Socket: (void (^)(C4Socket*))callback {
    auto socket = _c4socket.load();
    if (socket)
        callback(socket);
}

- (void) start NW_API_AVAILABLE {
    dispatch_async(_queue, ^{
        if (_logic.error) {
            // PAC resolution must have failed. Give up.
            [self closeWithError: _logic.error];
            return;
        }
        [self connect];
    });
}

- (void) connect NW_API_AVAILABLE {
    [self clearHTTPState];
    
    if (_networkInterface) {
        [self _resolveNetworkInterface];
    } else {
        [self _connect];
    }
}

- (void) _resolveNetworkInterface NW_API_AVAILABLE {
    _interfaceResolver = [[CBLInterfaceResolver alloc] initWithInterface: _networkInterface
                                                                   queue: _queue
                                                              completion: ^(CBLInterfaceResolver* resolver,
                                                                            nw_interface_t _Nullable interface)
     {
        if (resolver != _interfaceResolver)
            return; // resolver was cancelled
        
        _nwInterface = interface;
        if (interface) {
            [self _connect];
        } else {
            NSString* msg = $sprintf(@"Failed to find network interface %@", _networkInterface);
            CBLWarnError(WebSocket, @"%@: %@", self, msg);
            NSError* error = [NSError errorWithDomain: NSPOSIXErrorDomain
                                                 code: ENODEV
                                             userInfo: @{NSLocalizedDescriptionKey : msg}];
            [self closeWithError: error];
        }
    }];
}

// Opens the TCP connection.
// This may be called more than once if the initial HTTP response is a redirect or requires auth.
- (void) _connect NW_API_AVAILABLE {
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                             NW_PARAMETERS_DEFAULT_CONFIGURATION);
    
    if (_logic.proxyType == kCBLHTTPProxy) {
        [self setupHTTPProxyProtocol: params];
    } else if (_logic.useTLS) {
        nw_protocol_stack_t protocols = nw_parameters_copy_default_protocol_stack(params);
        nw_protocol_options_t tls = [self createTLSProtocol];
        nw_protocol_stack_prepend_application_protocol(protocols, tls);
    }
    
    if (_nwInterface) {
        nw_interface_type_t type = nw_interface_get_type(_nwInterface);
        CBLLogVerbose(WebSocket, @"%@ Set require network interface '%@' (type = %d) ...", self, _networkInterface, type);
        nw_parameters_require_interface(params, _nwInterface);
    }
    
    const char* cHost = [_logic.directHost cStringUsingEncoding: NSUTF8StringEncoding];
    const char* cPort = [$sprintf(@"%ld", (long)_logic.directPort) cStringUsingEncoding: NSUTF8StringEncoding];
    nw_endpoint_t endpoint = nw_endpoint_create_host(cHost, cPort);
    nw_connection_t connection = nw_connection_create(endpoint, params);
    nw_connection_set_queue(connection, _queue);
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t err) {
        CBLLogVerbose(WebSocket, @"%@ Connection state has changed (state = %d)", self, state);
        switch (state) {
            case nw_connection_state_waiting:
                // Note:
                // If the connection is stuck in this state without an error,
                // LiteCore will close the connection after the connection timeout.
                break;
            case nw_connection_state_preparing:
                break;
            case nw_connection_state_ready:
                [self sendWebSocketRequest];
                break;
            case nw_connection_state_failed:
                break;
            case nw_connection_state_cancelled:
                [_disposeCondition lock];
                [_disconnectingConnections removeObject: connection];
                [_disposeCondition signal];
                [_disposeCondition unlock];
                break;
            default:
                break;
        };
        
        if (err) {
            NSError* error = [self convertNWError: err];
            CBLLogVerbose(WebSocket, @"%@ Connection has an error : %@", self, error);
            [self closeWithError: error];
            return;
        }
    });
    
    _connection = connection;
    
    [self read];
    nw_connection_start(_connection);
}

#pragma mark - HTTP Proxy:

/**
 Setup HTTP Proxy Protocol which will send the HTTP CONNECT request to the HTTP Proxy Server as a handshake process.
 In the start handler, the handler will return 'will-mark-ready' which means that the connection will not be ready until
 the proxy handshake process is done. In the input handler, when the response from the proxy is completely received,
 the protocol will mark the connection as ready and set itself as a pass through protocol. Also before marking the
 connection as ready, if the TLS is used, the TLS protocol will be added to the protocol stack.
 */
- (void) setupHTTPProxyProtocol: (nw_parameters_t)params NW_API_AVAILABLE {
    nw_protocol_definition_t definition = nw_framer_create_definition("HTTPProxy", NW_FRAMER_CREATE_FLAGS_DEFAULT,
                                                                      [self httpProxyFramerStartHandler]);
    nw_protocol_options_t proxyProtocol = nw_framer_create_options(definition);
    nw_protocol_stack_t protocols = nw_parameters_copy_default_protocol_stack(params);
    nw_protocol_stack_prepend_application_protocol(protocols, proxyProtocol);
}

- (nw_framer_start_handler_t) httpProxyFramerStartHandler NW_API_AVAILABLE {
    return ^nw_framer_start_result_t(nw_framer_t _Nonnull framer) {
        nw_framer_set_output_handler(framer, [self httpProxyFramerOutputHandler] );
        nw_framer_set_input_handler(framer, [self httpProxyFramerInputHandler]);
        
        // Send CONNECT request (This will write to the TCP layer directly):
        nw_framer_async(framer, ^{
            CBLLogInfo(WebSocket, @"%@ Connecting to HTTP proxy %@:%d...", self, _logic.directHost, _logic.directPort);
            _connectingToProxy = YES;
            _logic.useProxyCONNECT = YES;
            NSData* data = _logic.HTTPRequestData;
            nw_framer_write_output(framer, (uint8_t*)data.bytes, data.length);
        });
        
        return nw_framer_start_result_will_mark_ready;
    };
}

- (nw_framer_output_handler_t) httpProxyFramerOutputHandler NW_API_AVAILABLE {
    return ^(nw_framer_t _Nonnull framer,
             nw_framer_message_t _Nonnull message,
             size_t message_length,
             bool is_complete) { };
}

- (nw_framer_input_handler_t) httpProxyFramerInputHandler NW_API_AVAILABLE {
    return ^size_t(nw_framer_t _Nonnull framer) {
        nw_framer_parse_input(framer, 0, kReadBufferSize, nil, ^size_t(uint8_t* _Nullable buffer,
                                                                       size_t buffer_length,
                                                                       bool is_complete) {
            [self receivedHTTPResponseBytes: buffer length: buffer_length];
            
            if (_connectedThruProxy) {
                // If the TLS is used, add the TLS protocol:
                if (_logic.useTLS) {
                    nw_protocol_options_t tls = [self createTLSProtocol];
                    nw_framer_prepend_application_protocol(framer, tls);
                }
                
                // Proxy Protocol is no longer needed:
                nw_framer_pass_through_input(framer);
                nw_framer_pass_through_output(framer);
                
                // Now mark the connection as ready:
                nw_framer_mark_ready(framer);
            }
            
            return buffer_length;
        });
        return 0;
    };
}

#pragma mark - Authentication

- (void) setupAuth {
    Dict auth = _options[kC4ReplicatorOptionAuthentication].asDict();
    if (!auth)
        return;
    
    NSString* authType = slice2string(auth[kC4ReplicatorAuthType].asString());
    if (authType == nil || [authType isEqualToString: @kC4AuthTypeBasic]) {
        NSString* username = slice2string(auth[kC4ReplicatorAuthUserName].asString());
        NSString* password = slice2string(auth[kC4ReplicatorAuthPassword].asString());
        if (username && password) {
            _logic.credential = [NSURLCredential credentialWithUser: username
                                                           password: password
                                                     persistence: NSURLCredentialPersistenceNone];
            return;
        }
    }
    
#ifdef COUCHBASE_ENTERPRISE
    else if ([authType isEqualToString: @kC4AuthTypeClientCert]) {
        C4Slice certData = auth[kC4ReplicatorAuthClientCert].asData();
        if (certData.buf) {
            C4Error err = {};
            C4Cert* c4cert = c4cert_fromData(certData, &err);
            if (c4cert) {
                NSError* error;
                if (@available(macOS 10.12, iOS 10.0, *)) {
                    _clientIdentity = toSecIdentityWithCertChain(c4cert, &error);
                    if (_clientIdentity) {
                        c4cert_release(c4cert);
                        return;
                    }
                    CBLWarnError(Sync, @"Couldn't lookup the identity from the KeyChain: %@", error);
                } else {
                    CBLWarnError(Sync, @"Client Cert Auth is not supported by macOS < 10.12 and iOS < 10.0");
                }
                c4cert_release(c4cert);
            } else {
                NSError* error;
                convertError(err, &error);
                CBLWarnError(Sync, @"Couldn't create C4Cert from the certificate data: %@", error);
            }
        }
    }
#endif
    CBLWarn(Sync, @"Unknown auth type or missing parameters for auth");
}

#pragma mark - TLS:

// Sets the TLS/SSL settings of the streams, if necessary.
// This gets called again after connecting to a proxy, to configure the TLS settings for the
// actual server.
- (nw_protocol_options_t) createTLSProtocol NW_API_AVAILABLE {
    assert(_logic.useTLS);
    nw_protocol_options_t tls = nw_tls_create_options();
    sec_protocol_options_t options = nw_tls_copy_sec_protocol_options(tls);
    if (_connectedThruProxy) {
        const char* cHost = [_logic.directHost cStringUsingEncoding: NSUTF8StringEncoding];
        sec_protocol_options_set_tls_server_name(options, cHost);
    }
    
#ifdef COUCHBASE_ENTERPRISE
    if (_clientIdentity.count > 0) {
        SecIdentityRef idRef = (__bridge SecIdentityRef)_clientIdentity[0];
        
        NSMutableArray* certs = [_clientIdentity mutableCopy];
        [certs removeObjectAtIndex: 0];
        CFArrayRef certsRef = (__bridge CFArrayRef)certs;
        
        sec_identity_t identity = sec_identity_create_with_certificates(idRef, certsRef);
        sec_protocol_options_set_local_identity(options, identity);
    }
#endif
    
    bool custom = false;
    if (_options[kC4ReplicatorOptionPinnedServerCert]) {
        custom = true;
    }
  
#ifdef COUCHBASE_ENTERPRISE
    if (_options[kC4ReplicatorOptionOnlySelfSignedServerCert].asBool()) {
        custom = true;
    }
#endif
    
    if (custom) {
        sec_protocol_options_set_verify_block(options, ^(sec_protocol_metadata_t _Nonnull metadata,
                                                         sec_trust_t _Nonnull trust_ref,
                                                         sec_protocol_verify_complete_t _Nonnull complete) {
            SecTrustRef trust = sec_trust_copy_ref(trust_ref);
            Assert(trust);
            bool success = [self checkSSLCert: trust];
            complete(success);
            CFRelease(trust);
        }, _queue);
    }
    return tls;
}

- (BOOL) checkSSLCert: (SecTrustRef)trust {
    [self updateServerCertificateFromTrust: trust];

    NSURL* url = _logic.URL;
    auto check = [[CBLTrustCheck alloc] initWithTrust: trust
                                                 host: url.host
                                                 port: url.port.shortValue];
    
#ifdef COUCHBASE_ENTERPRISE
    BOOL acceptOnlySelfSignedCert = _options[kC4ReplicatorOptionOnlySelfSignedServerCert].asBool();
#endif
    Value pin = _options[kC4ReplicatorOptionPinnedServerCert];
    if (pin) {
        check.pinnedCertData = slice(pin.asData()).copiedNSData();
        Assert(check.pinnedCertData, @"Invalid value for replicator %s property (must be NSData)",
               kC4ReplicatorOptionPinnedServerCert);
    }
#ifdef COUCHBASE_ENTERPRISE
    else if (!acceptOnlySelfSignedCert)  {
        // CFStream validates the certs (kCFStreamSSLValidatesCertificateChain = true)
        return true;
    }
#endif
    
    NSError* error;
#ifdef COUCHBASE_ENTERPRISE
    NSURLCredential* credentials = !pin && acceptOnlySelfSignedCert ?
        [check acceptOnlySelfSignedCert: &error] :
        [check checkTrust: &error];
#else
    NSURLCredential* credentials = [check checkTrust: &error];
#endif
    
    if (!credentials) {
        CBLWarn(WebSocket, @"TLS handshake failed: %@", error.localizedDescription);
        return false;
    } else
        CBLLogVerbose(WebSocket, @"TLS handshake succeeded");
    
    return true;
}

- (void) updateServerCertificateFromTrust: (SecTrustRef)trust {
    if (trust != NULL) {
        if (SecTrustGetCertificateCount(trust) > 0) {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 120000 || __IPHONE_OS_VERSION_MAX_REQUIRED >= 150000
            if (@available(macOS 12.0, iOS 15.0, *)) {
                CFArrayRef certs = SecTrustCopyCertificateChain(trust);
                SecCertificateRef cert = (SecCertificateRef)CFArrayGetValueAtIndex(certs, 0);
                _replicator.serverCertificate = cert;
                CFRelease(certs);
            } else
#endif
            {
                SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, 0);
                _replicator.serverCertificate = cert;
            }
        }
        else
            CBLWarn(WebSocket, @"SecTrust has no certificates"); // Shouldn't happen
    }
}

#pragma mark - HTTP / WebSocket:

- (void) clearHTTPState {
    _gotResponseHeaders = false;
    if (_httpResponse)
        CFRelease(_httpResponse);
    _httpResponse = CFHTTPMessageCreateEmpty(NULL, false);
}

// Sends the initial WebSocket HTTP handshake request.
- (void) sendWebSocketRequest NW_API_AVAILABLE {
    CBLLogInfo(WebSocket, @"%@ Send WebSocket request to %@:%d...", self, _logic.URL.host, _logic.port);
    
    uint8_t nonceBytes[16];
    (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(nonceBytes), nonceBytes);
    NSData* nonceData = [NSData dataWithBytes: nonceBytes length: sizeof(nonceBytes)];
    NSString* nonceKey = [nonceData base64EncodedStringWithOptions: 0];
    _expectedAcceptHeader = [[self class] webSocketAcceptHeaderForKey: nonceKey];
    
    // Construct the HTTP request:
    NSString* headerCookie = nil;
    for (Dict::iterator header(_options[kC4ReplicatorOptionExtraHeaders].asDict()); header; ++header) {
        NSString* keyString = slice2string(header.keyString());
        NSString* valueString = slice2string(header.value().asString());

        if ([keyString isEqualToString: @"Cookie"])
            headerCookie = valueString; // extract if any cookie in header
        else
            _logic[keyString] = valueString;
    }

    NSMutableString* cookies = [NSMutableString string];
    if (headerCookie.length > 0)
        [cookies appendFormat: @"%@;", headerCookie];

    slice sessionCookie = _options[kC4ReplicatorOptionCookies].asString();
    if (sessionCookie.buf)
        [cookies appendFormat: @"%@;", sessionCookie.asNSString()];

    NSError* error = nil;
    NSString* cookie = [_db getCookies: _remoteURL error: &error];
    if (error) {
        // in case database is not open: CBL-2657
        CBLWarn(Sync, @"Error while fetching cookies: %@", error);
        [self closeWithError: error];
        return;
    }

    if (cookie.length > 0)
        [cookies appendString: cookie];

    if (cookies.length > 0)
        [_logic setValue: cookies forHTTPHeaderField: @"Cookie"];
    
    _logic[@"Connection"] = @"Upgrade";
    _logic[@"Upgrade"] = @"websocket";
    _logic[@"Sec-WebSocket-Version"] = @"13";
    _logic[@"Sec-WebSocket-Key"] = nonceKey;

    slice protocols = _options[kC4SocketOptionWSProtocols].asString();
    if (protocols)
        _logic[@"Sec-WebSocket-Protocol"] = protocols.asNSString();

    [self writeData: _logic.HTTPRequestData completion: nil];
}

// Parses the HTTP response.
- (void) receivedHTTPResponseBytes: (const void*)bytes length: (size_t)length NW_API_AVAILABLE {
    CBLLogVerbose(WebSocket, @"Received %zu bytes of HTTP response", length);
    
    if (!CFHTTPMessageAppendBytes(_httpResponse, (const UInt8*)bytes, length)) {
        // Error reading response!
        [self closeWithCode: kWebSocketCloseProtocolError reason: @"Unparseable HTTP response"];
        return;
    }
    
    if (CFHTTPMessageIsHeaderComplete(_httpResponse)) {
        _gotResponseHeaders = YES;
        auto httpResponse = _httpResponse;
        _httpResponse = nullptr;
        [_logic receivedResponse: httpResponse];
        if (_logic.shouldRetry) {
            // Retry the connection, due to a redirect or auth challenge:
            [self disconnect];
            [self connect];
        } else if (_connectingToProxy) {
            [self receivedProxyHTTPResponse: httpResponse];
        } else {
            [self receivedHTTPResponse: httpResponse];
        }
        CFRelease(httpResponse);
    }
}

// Handles a proxy HTTP response, triggering the WebSocket handshake if the tunnel is open.
- (void) receivedProxyHTTPResponse: (CFHTTPMessageRef)httpResponse NW_API_AVAILABLE {
    NSInteger httpStatus = _logic.httpStatus;
    if (httpStatus != 200) {
        [self closeWithCode: (C4WebSocketCloseCode)httpStatus
                     reason: $sprintf(@"Proxy: %@", _logic.httpStatusMessage)];
        return;
    }

    // Now send the actual WebSocket GET request, over the open stream:
    _connectedThruProxy = YES;
    _connectingToProxy = NO;
    
    _logic.proxySettings = nil;
    _logic.useProxyCONNECT = NO;
    
    [self clearHTTPState];
    CBLLogInfo(WebSocket, @"%@ Proxy CONNECT to %@:%d...", self, _logic.URL.host, _logic.port);
}

// Handles the WebSocket handshake HTTP response.
- (void) receivedHTTPResponse: (CFHTTPMessageRef)httpResponse NW_API_AVAILABLE {
    // Post the response headers to LiteCore:
    NSDictionary *headers =  CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(httpResponse));
    
    NSString* cookie = headers[@"Set-Cookie"];
    if (cookie.length > 0) {
        NSArray* cookies = [CBLNWWebSocket parseCookies: cookie];

        // Save to LiteCore
        for (NSString* cookieStr in cookies) {
            [_db saveCookie: cookieStr url: _remoteURL];
        }

        if (cookies.count > 0) {
            NSMutableDictionary* newHeaders = [headers mutableCopy];
            newHeaders[@"Set-Cookie"] = cookies;
            headers = newHeaders;
        }
    }
    
    NSInteger httpStatus = _logic.httpStatus;
    Encoder enc;
    enc << headers;
    alloc_slice headersFleece = enc.finish();
    [self callC4Socket: ^(C4Socket* socket) {
        c4socket_gotHTTPResponse(socket, (int)httpStatus, {headersFleece.buf, headersFleece.size});
    }];

    if (httpStatus != 101) {
        // Unexpected HTTP status:
        C4WebSocketCloseCode closeCode = kWebSocketClosePolicyError;
        if (httpStatus >= 300 && httpStatus < 1000)
            closeCode = (C4WebSocketCloseCode)httpStatus;
        [self closeWithCode: closeCode reason: _logic.httpStatusMessage];

    } else if (!checkHeader(headers, @"Connection", @"Upgrade", NO)) {
        [self closeWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Connection' header"];
    } else if (!checkHeader(headers, @"Upgrade", @"websocket", NO)) {
        [self closeWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Upgrade' header"];
    } else if (!checkHeader(headers, @"Sec-WebSocket-Accept", _expectedAcceptHeader, YES)) {
        [self closeWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Sec-WebSocket-Accept' header"];
    } else {
        // Now I can start the WebSocket protocol:
        [self connected: headers];
    }
}

// Notifies LiteCore that the WebSocket is connected.
- (void) connected: (NSDictionary*)responseHeaders {
    CBLLogInfo(WebSocket, @"CBLWebSocket CONNECTED!");
    [self callC4Socket: ^(C4Socket *socket) {
        c4socket_opened(socket);
    }];
}

// Tests whether a header value matches the expected string.
static BOOL checkHeader(NSDictionary* headers, NSString* header, NSString* expected, BOOL caseSens) {
    NSString* value = headers[header];
    if (caseSens)
        return [value isEqualToString: expected];
    else
        return value && [value caseInsensitiveCompare: expected] == 0;
}

// Returns the correct Accept: response header value for a given nonce.
+ (nullable NSString*) webSocketAcceptHeaderForKey: (NSString*)key {
    key = [key stringByAppendingString: @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
    NSData* data = [key dataUsingEncoding: NSASCIIStringEncoding];
    if (!data)
        return nil;
    unsigned char result[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([data bytes], (CC_LONG)[data length], result);
    data = [NSData dataWithBytes:result length:CC_SHA1_DIGEST_LENGTH];
    return [data base64EncodedStringWithOptions: 0];
}

#pragma mark - READ / WRITE:

- (dispatch_data_t) createDispatchDataFromNSData: (NSData*)data {
    if (!data)
        return nil;
    
    Byte bytes[data.length];
    [data getBytes:bytes length:data.length];
    return dispatch_data_create(bytes, data.length, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
}

- (NSData*) nsdataFromDispatchData: (dispatch_data_t)dispatchData {
    if (dispatchData == nil) {
        return nil;
    }
    
    const void *buffer = NULL;
    size_t size = 0;
    dispatch_data_t new_data_file = dispatch_data_create_map(dispatchData, &buffer, &size);
    if(new_data_file) {/* to avoid warning really - since dispatch_data_create_map demands we care about the return arg */}
    NSData *nsdata = [[NSData alloc] initWithBytes:buffer length:size];
    return nsdata;
}

- (NSError*) convertNWError: (nw_error_t)error NW_API_AVAILABLE {
    if (!error)
        return nil;
    
    int code = nw_error_get_error_code(error);
    NSErrorDomain domain;
    nw_error_domain_t nwdomain = nw_error_get_error_domain(error);
    if (nwdomain == nw_error_domain_posix) {
        domain = NSPOSIXErrorDomain;
    } else if (nwdomain == nw_error_domain_tls) {
        domain = NSOSStatusErrorDomain;
    } else if (nwdomain == nw_error_domain_dns) {
        domain = NSURLErrorDomain;
        code = NSURLErrorDNSLookupFailed;
    } else {
        domain = NSURLErrorDomain;
        code = NSURLErrorUnknown;
    }
    return [[NSError alloc] initWithDomain: domain code: code  userInfo: nil];
}

// callback from C4Socket
- (void) writeAndFree: (C4SliceResult) allocatedData NW_API_AVAILABLE {
    NSData* data = [NSData dataWithBytesNoCopy: (void*)allocatedData.buf
                                        length: allocatedData.size
                                  freeWhenDone: NO];
    CBLLogVerbose(WebSocket, @">>> sending %zu bytes...", allocatedData.size);
    dispatch_async(_queue, ^{
        [self writeData: data completion: ^(NSError* error) {
            if (error) {
                [self closeWithError: error];
                return;
            }
            
            size_t size = allocatedData.size;
            c4slice_free(allocatedData);
            CBLLogVerbose(WebSocket, @"    (...sent %zu bytes)", size);
            
            [self callC4Socket: ^(C4Socket *socket) {
                c4socket_completedWrite(socket, size);
            }];
        }];
    });
}

- (void) writeData: (NSData*)data completion: (void (^)(NSError* _Nullable error))completion NW_API_AVAILABLE {
    CBLLogVerbose(WebSocket, @"Write...");
    dispatch_data_t d = [self createDispatchDataFromNSData: data];
    nw_content_context_t context = nw_content_context_create("data");
    nw_connection_send(_connection, d, context, true, ^(nw_error_t _Nullable error) {
        NSError* err = [self convertNWError: error];
        if (completion) {
            completion(err);
        }
    });
}

// Returns true if there is too much unhandled WebSocket data in memory
// and we should stop reading from the socket.
- (bool) readThrottled {
    return _receivedBytesPending >= kMaxReceivedBytesPending;
}

- (void) read NW_API_AVAILABLE {
    CBLLogVerbose(WebSocket, @"Read...");
    
    if (!_connection) {
        return;
    }
    
    nw_connection_receive(_connection, 0, kReadBufferSize,
                          ^(dispatch_data_t  _Nullable content,
                            nw_content_context_t  _Nullable context,
                            bool is_complete,
                            nw_error_t  _Nullable error) {
        if (!_connection)
            return;
        
        if (error) {
            [self closeWithError: [self convertNWError: error]];
            return;
        }
        
        if (!content)
            return;
        
        NSData* data = (NSData*)content;
        if (!_gotResponseHeaders)
            [self receivedHTTPResponseBytes: data.bytes length: data.length];
        else
            [self receivedBytes: data.bytes length: data.length];
        
        if (!self.readThrottled) {
            [self read];
        }
    });
}

- (void) receivedBytes: (const void*)bytes length: (size_t)length {
    self->_receivedBytesPending += length;
    CBLLogVerbose(WebSocket, @"<<< received %zu bytes [now %zu pending]",
                  (size_t)length, self->_receivedBytesPending);
    [self callC4Socket: ^(C4Socket *socket) {
        c4socket_received(socket, {bytes, length});
    }];
}

// callback from C4Socket
- (void) completedReceive: (size_t)byteCount NW_API_AVAILABLE {
    dispatch_async(_queue, ^{
        bool wasThrottled = self.readThrottled;
        self->_receivedBytesPending -= byteCount;
        if (wasThrottled && !self.readThrottled)
            [self read];
    });
}

// callback from C4Socket
- (void) closeSocket NW_API_AVAILABLE {
    CBLLogInfo(WebSocket, @"%@ CBLWebSocket closeSocket requested", self);
    dispatch_async(_queue, ^{
        if (_connection) {
            [self closeWithError: nil];
        }
    });
}

- (void) disconnect NW_API_AVAILABLE {
    CBLLogVerbose(WebSocket, @"%@: Disconnect", self);
    if (_connection) {
        [_disposeCondition lock];
        [_disconnectingConnections addObject: _connection];
        nw_connection_cancel(_connection);
        _connection = nil;
        [_disposeCondition signal];
        [_disposeCondition unlock];
    }
}

#pragma mark - CLOSING / ERROR HANDLING:

// Closes the connection and passes a WebSocket/HTTP status code to LiteCore.
- (void) closeWithCode: (C4WebSocketCloseCode)code reason: (NSString*)reason NW_API_AVAILABLE {
    if (code == kWebSocketCloseNormal) {
        [self closeWithError: nil];
        return;
    }
    
    if (!_connection) {
        CBLLogVerbose(Sync, @"%@ Websocket is already closed. Ignoring the close with code.", self);
        return;
    }
    
    CBLLogInfo(WebSocket, @"CBLWebSocket CLOSING WITH STATUS %d \"%@\"", (int)code, reason);
    
    [self disconnect];
    nsstring_slice reasonSlice(reason);
    [self c4SocketClosed: c4error_make(WebSocketDomain, code, reasonSlice)];
}

// Closes the connection and passes the NSError (if any) to LiteCore.
- (void) closeWithError: (NSError*)error NW_API_AVAILABLE {
    // This function is always called from queue.
    if (!_connection) {
        CBLLogVerbose(Sync, @"%@ Websocket is already closed. Ignoring the close with error.", self);
        return;
    }
    
    C4Error c4err;
    if (error) {
        CBLLogInfo(WebSocket, @"CBLWebSocket CLOSED WITH ERROR: %@", error.my_compactDescription);
        convertError(error, &c4err);
    } else {
        CBLLogInfo(WebSocket, @"CBLWebSocket CLOSED");
        c4err = {};
    }
    
    [self disconnect];
    [self c4SocketClosed: c4err];
}

- (void) c4SocketClosed: (C4Error)c4err {
    [self callC4Socket: ^(C4Socket *socket) {
        c4socket_closed(socket, c4err);
    }];
}

#pragma mark - Helper

+ (NSArray*) parseCookies: (NSString*) cookieStr {
    Assert(cookieStr.length > 0, @"Trying to parse empty cookie string");
    
    NSArray* rawAttrs = [cookieStr componentsSeparatedByString: @";"];
    
    NSMutableArray *attrs = [NSMutableArray arrayWithCapacity: [rawAttrs count]];
    for (NSString* rawAttr in rawAttrs) {
        // trims the attribute
        NSString* attr = [rawAttr stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // replace comma with ^G(bell) in Date
        if ([attr hasPrefix: @"Expires"] || [attr hasPrefix: @"expires"]) {
            NSRange range = [attr rangeOfString: @","];
            if (range.location != NSNotFound)
                attr = [attr stringByReplacingCharactersInRange: range withString: @"^G"];
        }
        [attrs addObject: attr];
    }
    
    // separate out with cookie boundaries
    NSArray* rawCookies = [[attrs componentsJoinedByString: @";"] componentsSeparatedByString: @","];
    NSMutableArray *cookies = [NSMutableArray arrayWithCapacity: [rawCookies count]];
    for (NSString* rawCookie in rawCookies) {
        // trim the cookie
        NSString* cookie = [rawCookie stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // replace the previous ^G with comma
        NSRange range = [cookie rangeOfString: @"^G"];
        if (range.location != NSNotFound)
            cookie = [cookie stringByReplacingCharactersInRange: range withString: @","];
        
        [cookies addObject: cookie];
    }
    return [NSArray arrayWithArray: cookies];
}

@end

#pragma mark - CBLInterfaceResolver:

@implementation CBLInterfaceResolver {
    nw_path_monitor_t _monitor;
    dispatch_queue_t _queue;
    bool _isCancelled;
}

- (instancetype) initWithInterface: (NSString*)interfaceName
                             queue: (dispatch_queue_t)queue
                        completion: (void (^)(CBLInterfaceResolver* resolver,
                                              nw_interface_t _Nullable interface))completion
{
    self = [super init];
    if (self) {
        _queue = queue;
        _monitor = nw_path_monitor_create();
        nw_path_monitor_set_queue(_monitor, _queue);
        
        __weak id weakSelf = self;
        nw_path_monitor_set_update_handler(_monitor, ^(nw_path_t  _Nonnull path) {
            id strongSelf = weakSelf;
            @synchronized (strongSelf) {
                if (_isCancelled)
                    return;
                
                __block nw_interface_t result = nil;
                nw_path_enumerate_interfaces(path, ^bool(nw_interface_t  _Nonnull interface) {
                    NSString* name = [NSString stringWithUTF8String: nw_interface_get_name(interface)];
                    if ([interfaceName isEqualToString: name]) {
                        result = interface;
                        return false;
                    }
                    return true;
                });
                
                completion(strongSelf, result);
                [self cancel]; // Resolve only once
            }
        });
        
        nw_path_monitor_start(_monitor);
    }
    return self;
}

- (void) dealloc {
    [self cancel];
}

- (void) cancel NW_API_AVAILABLE {
    @synchronized (self) {
        if (!_isCancelled) {
            _isCancelled = true;
            nw_path_monitor_cancel(_monitor);
        }
    }
}

@end
