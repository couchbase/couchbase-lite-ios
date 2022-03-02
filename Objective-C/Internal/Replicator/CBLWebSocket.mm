//
//  CBLWebSocket.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLWebSocket.h"
#import "CBLHTTPLogic.h"
#import "CBLTrustCheck.h"
#import "CBLCoreBridge.h"
#import "CBLStatus.h"
#import "CBLReplicatorConfiguration.h"  // for the options constants
#import "CBLReplicator+Internal.h"
#import "CBLDatabase+Internal.h"
#import "c4Socket.h"
#import "MYURLUtils.h"
#import "fleece/Fleece.hh"
#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#import <memory>
#import <net/if.h>
#import <netdb.h>
#import <vector>
#import "CollectionUtils.h"
#import "CBLURLEndpoint.h"
#import "CBLStringBytes.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLCert.h"
#endif

extern "C" {
#import "MYAnonymousIdentity.h"
#import "MYErrorUtils.h"
}

using namespace fleece;

// Number of bytes to read from the socket at a time
static constexpr size_t kReadBufferSize = 32 * 1024;

// Max number of bytes read that haven't been processed by LiteCore yet.
// Beyond this point, I will stop reading from the socket, sending backpressure to the peer.
static constexpr size_t kMaxReceivedBytesPending = 100 * 1024;

struct PendingWrite {
    PendingWrite(NSData *d, void (^h)())
    :data(d)
    ,completionHandler(h)
    { }

    NSData *data;
    size_t bytesWritten {0};
    void (^completionHandler)();
};

@interface CBLWebSocket () <NSStreamDelegate>

// Socket descriptor for openning connection when a network interface is specified
@property (atomic) int sockfd;

@end

@implementation CBLWebSocket
{
    AllocedDict _options;
    dispatch_queue_t _queue;
    NSString* _expectedAcceptHeader;
    CBLHTTPLogic* _logic;
    std::atomic<C4Socket*> _c4socket;
    CFHTTPMessageRef _httpResponse;
    id _keepMeAlive;

    NSInputStream* _in;
    NSOutputStream* _out;
    uint8_t* _readBuffer;
    std::vector<PendingWrite> _pendingWrites;
    bool _checkSSLCert;
    bool _hasBytes, _hasSpace;
    size_t _receivedBytesPending;
    bool _gotResponseHeaders;
    BOOL _connectingToProxy;
    BOOL _connectedThruProxy;
    
    CBLReplicator* _replicator;
    CBLDatabase* _db;
    NSURL* _remoteURL;
    
    NSArray* _clientIdentity;
    
    BOOL _closing;
    
    NSString* _networkInterface;
    struct addrinfo* _addr;
    dispatch_queue_t _socketConnectQueue;
}

@synthesize sockfd=_sockfd;

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

static void doOpen(C4Socket* s, const C4Address* addr, C4Slice optionsFleece, void *context) {
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
        auto socket = [[CBLWebSocket alloc] initWithURL: url
                                               c4socket: s
                                                options: optionsFleece
                                                context: context];
        c4Socket_setNativeHandle(s, (__bridge void*)socket);
        socket->_keepMeAlive = socket;          // Prevents dealloc until doDispose is called
        [socket start];
    }
}

static CBLWebSocket* getWebSocket(C4Socket *s) {
    return (__bridge CBLWebSocket*)c4Socket_getNativeHandle(s);
}

static void doClose(C4Socket* s) {
    [getWebSocket(s) closeSocket];
}

static void doWrite(C4Socket* s, C4SliceResult allocatedData) {
    [getWebSocket(s) writeAndFree: allocatedData];
}

static void doCompletedReceive(C4Socket* s, size_t byteCount) {
    [getWebSocket(s) completedReceive: byteCount];
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
        _replicator = (__bridge CBLReplicator*)context;
        _db = _replicator.config.database;
        _remoteURL = $castIf(CBLURLEndpoint, _replicator.config.target).url;
        _readBuffer = (uint8_t*)malloc(kReadBufferSize);
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url];
        request.HTTPShouldHandleCookies = NO;
        _logic = [[CBLHTTPLogic alloc] initWithURLRequest: request];
        _logic.handleRedirects = YES;

        slice proxy = _options["HTTPProxy"_sl].asString();      //TODO: Add to c4Replicator.h
        if (proxy) {
            NSURL* proxyURL = [NSURL URLWithDataRepresentation: proxy.uncopiedNSData()
                                                 relativeToURL: nil];
            if (![_logic setProxyURL: proxyURL]) {
                CBLWarn(Sync, @"Invalid replicator HTTPProxy setting <%.*s>",
                        (int)proxy.size, (char *)proxy.buf);
            }
        }

        [self setupAuth];

        NSString* queueName = [NSString stringWithFormat: @"WebSocket-%@:%u", url.host, _logic.port];
        _queue = dispatch_queue_create(queueName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        _sockfd = -1;
        _addr = nullptr;
        _networkInterface = _replicator.config.networkInterface;
        if (_networkInterface) {
            queueName = [NSString stringWithFormat: @"%@-SocketConnect", queueName];
            _socketConnectQueue = dispatch_queue_create(queueName.UTF8String, DISPATCH_QUEUE_SERIAL);
        }
    }
    return self;
}

- (void) dealloc {
    CBLLogVerbose(WebSocket, @"DEALLOC %@", self);
    Assert(!_in);
    Assert(_sockfd < 0);
    free(_readBuffer);
    if (_httpResponse)
        CFRelease(_httpResponse);
    if (_addr)
        freeaddrinfo(_addr);
}

- (void) dispose {
    CBLLogVerbose(WebSocket, @"C4Socket of %@ is being disposed", self);
    // This has to be done synchronously, because _c4socket will be freed when this method returns
    auto socket = _c4socket.exchange(nullptr);
    if (socket)
        c4Socket_setNativeHandle(socket, nullptr);
    // Remove the self-reference, so this object will be dealloced:
    _keepMeAlive = nil;
}

- (void) clearHTTPState {
    _gotResponseHeaders = _checkSSLCert = false;
    if (_httpResponse)
        CFRelease(_httpResponse);
    _httpResponse = CFHTTPMessageCreateEmpty(NULL, false);
}

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

- (void) callC4Socket: (void (^)(C4Socket*))callback {
    auto socket = _c4socket.load();
    if (socket)
        callback(socket);
}

#pragma mark - HANDSHAKE:

- (void) start {
    dispatch_async(_queue, ^{
        if (_logic.error) {
            // PAC resolution must have failed. Give up.
            [self closeWithError: _logic.error];
            return;
        }
        [self _connect];
    });
}

// Opens the TCP connection.
// This may be called more than once if the initial HTTP response is a redirect or requires auth.
- (void) _connect {
    _hasBytes = _hasSpace = false;
    _pendingWrites.clear();
    [self clearHTTPState];

    _connectingToProxy = (_logic.proxyType == kCBLHTTPProxy);
    _connectedThruProxy = NO;

    if (_networkInterface) {
        CBLLogInfo(WebSocket, @"%@ connecting thru network interface %@", self, _networkInterface);
        [self connectToHostWithName: _logic.directHost
                               port: _logic.directPort
                   networkInterface: _networkInterface];
        
    } else {
        NSInputStream *inStream;
        NSOutputStream *outStream;
        [NSStream getStreamsToHostWithName: _logic.directHost
                                      port: _logic.directPort
                               inputStream: &inStream
                              outputStream: &outStream];
        
        [self _connectWithInputStream: inStream outputStream: outStream];
    }
}

- (void) _connectWithInputStream: (NSInputStream*)inStream outputStream: (NSOutputStream*)outStream {
    _in = inStream;
    _out = outStream;
    
    CFReadStreamSetDispatchQueue((__bridge CFReadStreamRef)_in, _queue);
    CFWriteStreamSetDispatchQueue((__bridge CFWriteStreamRef)_out, _queue);
    _in.delegate = _out.delegate = self;
    
    [self configureSOCKS];
    [self configureTLS];
    
    [_in open];
    [_out open];

    if (_connectingToProxy) {
        CBLLogInfo(WebSocket, @"%@ connecting to HTTP proxy %@:%d...",
                   self, _logic.directHost, _logic.directPort);
        _logic.useProxyCONNECT = YES;
        [self writeData: _logic.HTTPRequestData completionHandler: nil];
    } else {
        CBLLogInfo(WebSocket, @"%@ connecting to %@:%d...", self, _logic.URL.host, _logic.port);
        [self _sendWebSocketRequest];
    }
}

- (void) connectToHostWithName: (NSString*)hostname
                          port: (NSInteger)port
              networkInterface: (NSString*)interface
{
    // Get address info:
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM;
    
    const char* cHost = [hostname cStringUsingEncoding: NSUTF8StringEncoding];
    const char* cPort = [$sprintf(@"%ld", (long)port) cStringUsingEncoding: NSUTF8StringEncoding];
    
    int res = getaddrinfo(cHost, cPort, &hints, &_addr);
    if (res) {
        NSString* msg = $sprintf(@"Failed to get address info with error %d", res);
        CBLWarnError(WebSocket, @"%@: %@", self, msg);
        [self closeWithError: addrInfoError(res, msg)];
        return;
    }
    
    CBLLogVerbose(WebSocket, @"%@: %@:%ld(%@) got address info as %@",
                  self, hostname, (long)port, interface, addrInfo(_addr));
    
    // Create socket:
    Assert(_sockfd < 0);
    _sockfd = socket(_addr->ai_family, _addr->ai_socktype, _addr->ai_protocol);
    if (_sockfd < 0) {
        int errNo = errno;
        NSString* msg = $sprintf(@"Failed to create socket with errno %d (%@)", errNo, addrInfo(_addr));
        CBLWarnError(WebSocket, @"%@: %@", self, msg);
        [self closeWithError: posixError(errNo, msg)];
        return;
    }
    
    // Set network interface:
    if (interface) {
        unsigned int index = if_nametoindex([interface cStringUsingEncoding: NSUTF8StringEncoding]);
        if (index == 0) {
            int errNo = errno;
            NSString* msg = $sprintf(@"Failed to find network interface %@ with errno %d", interface, errNo);
            CBLWarnError(WebSocket, @"%@: %@", self, msg);
            [self closeWithError: posixError(errNo, msg)];
            return;
        }
        int result = -1;
        switch (_addr->ai_family) {
            case AF_INET:
                result = setsockopt(_sockfd, IPPROTO_IP, IP_BOUND_IF, &index, sizeof(index));
                break;
            case AF_INET6:
                result = setsockopt(_sockfd, IPPROTO_IPV6, IPV6_BOUND_IF, &index, sizeof(index));
                break;
            default:
                CBLWarnError(WebSocket, @"%@: Address family %d is not supported", self, _addr->ai_family);
                result = -1;
                break;
        }
        if (result < 0) {
            int errNo = errno;
            NSString* msg = $sprintf(@"Failed to set network interface %@ with errno %d (%@)",
                                     interface, errNo, addrInfo(_addr));
            CBLWarnError(WebSocket, @"%@: %@", self, msg);
            [self closeWithError: posixError(errNo, msg)];
            return;
        }
    }
    
    // Connect:
    dispatch_async(_socketConnectQueue, ^{
        int sockfd = self.sockfd;
        if (sockfd < 0) {
            return; // Already disconnected
        }
        
        int status = connect(sockfd, _addr->ai_addr, _addr->ai_addrlen);
        
        if (status == 0) {
            dispatch_async(_queue, ^{
                if (_sockfd < 0)
                    return; // Already disconnected
                
                // Enable non-blocking mode on the socket:
                int flags = fcntl(_sockfd, F_GETFL);
                if (fcntl(_sockfd, F_SETFL, flags | O_NONBLOCK) < 0) {
                    int errNo = errno;
                    NSString* msg = $sprintf(@"Failed to enable non-blocking mode with errno %d", errNo);
                    CBLWarnError(WebSocket, @"%@: %@", self, msg);
                    [self closeWithError: posixError(errNo, msg)];
                    return;
                }
                
                // Create a pair steam with the socket:
                CFReadStreamRef readStream;
                CFWriteStreamRef writeStream;
                CFStreamCreatePairWithSocket(kCFAllocatorDefault, _sockfd, &readStream, &writeStream);
                
                CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
                CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
                
                NSInputStream* input = CFBridgingRelease(readStream);
                NSOutputStream* output = CFBridgingRelease(writeStream);
                
                // Connect with the streams:
                [self _connectWithInputStream: input outputStream: output];
            });
        } else {
            int errNo = errno;
            NSString* msg = interface ?
                $sprintf(@"Failed to connect via the specified network interface %@ with errno %d", interface, errNo) :
                $sprintf(@"Failed to connect with errno %d", errNo);
            CBLWarnError(WebSocket, @"%@: %@", self, msg);
            NSError* error = posixError(errNo, msg);
            dispatch_async(_queue, ^{
                [self closeWithError: error];
            });
        }
    });
}

static inline NSError* posixError(int errNo, NSString* msg) {
    return [NSError errorWithDomain: NSPOSIXErrorDomain
                               code: errNo
                           userInfo: @{NSLocalizedDescriptionKey : msg}];
}

static inline NSError* addrInfoError(int res, NSString* msg) {
    return [NSError errorWithDomain: (id)kCFErrorDomainCFNetwork
                               code: kCFHostErrorUnknown
                           userInfo: @{NSLocalizedDescriptionKey: msg,
                                       (id)kCFGetAddrInfoFailureKey: $sprintf(@"%d", res)}];
}

static inline NSString* addrInfo(const struct addrinfo* addr) {
    return $sprintf(@"family=%d, socktype=%d, protocol=%d",
                    addr->ai_family, addr->ai_socktype, addr->ai_protocol);
}

- (void) configureSOCKS {
    if (_logic.proxyType == kCBLSOCKSProxy) {
        CFReadStreamSetProperty((__bridge CFReadStreamRef)_in,
                                kCFStreamPropertySOCKSProxy,
                                (__bridge CFDictionaryRef)_logic.proxySettings);
    }
}

// Sets the TLS/SSL settings of the streams, if necessary.
// This gets called again after connecting to a proxy, to configure the TLS settings for the
// actual server.
- (void) configureTLS {
    _checkSSLCert = false;
    if (_logic.useTLS) {
        CBLLogVerbose(WebSocket, @"%@ enabling TLS", self);
        NSMutableDictionary* settings = [NSMutableDictionary dictionary];
        if (_connectedThruProxy)
            [settings setObject: _logic.directHost
                         forKey: (__bridge id)kCFStreamSSLPeerName];
        
        if (_options[kC4ReplicatorOptionPinnedServerCert])
            [settings setObject: @NO
                         forKey: (__bridge id)kCFStreamSSLValidatesCertificateChain];
      
#ifdef COUCHBASE_ENTERPRISE
        if (_options[kC4ReplicatorOptionOnlySelfSignedServerCert].asBool())
            [settings setObject: @NO
                         forKey: (__bridge id)kCFStreamSSLValidatesCertificateChain];
#endif
        
        if (_clientIdentity)
            [settings setObject: _clientIdentity
                         forKey: (__bridge id)kCFStreamSSLCertificates];
        
        if (![_in setProperty: settings
                       forKey: (__bridge NSString *)kCFStreamPropertySSLSettings]) {
            CBLWarnError(WebSocket, @"%@ failed to set SSL settings", self);
        }
        _checkSSLCert = true;
        
        // When using client proxy, the stream will be reset after setting
        // the SSL properties. Make sure to update the _hasSpace flag to reflect
        // the current status of the stream.
        _hasSpace = _out.hasSpaceAvailable;
    }
}

// Sends the initial WebSocket HTTP handshake request.
- (void) _sendWebSocketRequest {
    uint8_t nonceBytes[16];
    (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(nonceBytes), nonceBytes);
    NSData* nonceData = [NSData dataWithBytes: nonceBytes length: sizeof(nonceBytes)];
    NSString* nonceKey = [nonceData base64EncodedStringWithOptions: 0];
    _expectedAcceptHeader = [[self class] webSocketAcceptHeaderForKey: nonceKey];
    
    // Construct the HTTP request:
    for (Dict::iterator header(_options[kC4ReplicatorOptionExtraHeaders].asDict()); header; ++header)
        _logic[slice2string(header.keyString())] = slice2string(header.value().asString());
    
    slice sessionCookie = _options[kC4ReplicatorOptionCookies].asString();
    NSMutableString* cookies = [NSMutableString string];
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

    [self writeData: _logic.HTTPRequestData completionHandler: nil];
}

// Parses the HTTP response.
- (void) receivedHTTPResponseBytes: (const void*)bytes length: (size_t)length {
    CBLLogVerbose(WebSocket, @"Received %zu bytes of HTTP response", length);

    if (!CFHTTPMessageAppendBytes(_httpResponse, (const UInt8*)bytes, length)) {
        // Error reading response!
        [self closeWithCode: kWebSocketCloseProtocolError
                        reason: @"Unparseable HTTP response"];
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
            [self _connect];
        } else if (_connectingToProxy) {
            [self receivedProxyHTTPResponse: httpResponse];
        } else {
            [self receivedHTTPResponse: httpResponse];
        }
        CFRelease(httpResponse);
    }
}

// Handles a proxy HTTP response, triggering the WebSocket handshake if the tunnel is open.
- (void) receivedProxyHTTPResponse: (CFHTTPMessageRef)httpResponse {
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
    [self configureTLS];

    CBLLogInfo(WebSocket, @"%@ Proxy CONNECT to %@:%d...", self, _logic.URL.host, _logic.port);
    [self _sendWebSocketRequest];
}

// Handles the WebSocket handshake HTTP response.
- (void) receivedHTTPResponse: (CFHTTPMessageRef)httpResponse {
    // Post the response headers to LiteCore:
    NSDictionary *headers =  CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(httpResponse));
        
    NSString* cookie = headers[@"Set-Cookie"];
    if (cookie.length > 0) {
        NSArray* cookies = [CBLWebSocket parseCookies: cookie];
        
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
    [self callC4Socket:^(C4Socket *socket) {
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
        // TODO: Check Sec-WebSocket-Extensions for unknown extensions
        // Now I can start the WebSocket protocol:
        [self connected: headers];
    }
}

// Notifies LiteCore that the WebSocket is connected.
- (void) connected: (NSDictionary*)responseHeaders {
    CBLLogInfo(WebSocket, @"CBLWebSocket CONNECTED!");
    [self callC4Socket:^(C4Socket *socket) {
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

// Returns true if there is too much unhandled WebSocket data in memory
// and we should stop reading from the socket.
- (bool) readThrottled {
    return _receivedBytesPending >= kMaxReceivedBytesPending;
}

// callback from C4Socket
- (void) writeAndFree: (C4SliceResult) allocatedData {
    NSData* data = [NSData dataWithBytesNoCopy: (void*)allocatedData.buf
                                        length: allocatedData.size
                                  freeWhenDone: NO];
    CBLLogVerbose(WebSocket, @">>> sending %zu bytes...", allocatedData.size);
    dispatch_async(_queue, ^{
        [self writeData: data completionHandler: ^() {
            size_t size = allocatedData.size;
            c4slice_free(allocatedData);
            CBLLogVerbose(WebSocket, @"    (...sent %zu bytes)", size);
            [self callC4Socket:^(C4Socket *socket) {
                c4socket_completedWrite(socket, size);
            }];
        }];
    });
}

// Called when WebSocket data is received (NOT necessarily an entire message.)
- (void) receivedBytes: (const void*)bytes length: (size_t)length {
    self->_receivedBytesPending += length;
    CBLLogVerbose(WebSocket, @"<<< received %zu bytes [now %zu pending]",
                  (size_t)length, self->_receivedBytesPending);
    [self callC4Socket:^(C4Socket *socket) {
        c4socket_received(socket, {bytes, length});
    }];
}

// callback from C4Socket
- (void) completedReceive: (size_t)byteCount {
    dispatch_async(_queue, ^{
        bool wasThrottled = self.readThrottled;
        self->_receivedBytesPending -= byteCount;
        if (_hasBytes && wasThrottled && !self.readThrottled)
            [self doRead];
    });
}

// callback from C4Socket
- (void) closeSocket {
    CBLLogInfo(WebSocket, @"%@ CBLWebSocket closeSocket requested", self);
    dispatch_async(_queue, ^{
        if (_in || _out || _sockfd >= 0) {
            [self closeWithError: nil];
        }
    });
}

#pragma mark - CLOSING / ERROR HANDLING:

// Closes the connection and passes a WebSocket/HTTP status code to LiteCore.
- (void) closeWithCode: (C4WebSocketCloseCode)code reason: (NSString*)reason {
    if (code == kWebSocketCloseNormal) {
        [self closeWithError: nil];
        return;
    }
    if (!_in)
        return;

    CBLLogInfo(WebSocket, @"CBLWebSocket CLOSING WITH STATUS %d \"%@\"", (int)code, reason);
    [self disconnect];
    nsstring_slice reasonSlice(reason);
    [self c4SocketClosed: c4error_make(WebSocketDomain, code, reasonSlice)];
}

// Closes the connection and passes the NSError (if any) to LiteCore.
- (void) closeWithError: (NSError*)error {
    // This function is always called from queue.
    if (_closing) {
        CBLLogVerbose(Sync, @"%@ Websocket is already closing. Ignoring the close.", self);
        return;
    }
    _closing = YES;
    
    [self disconnect];

    C4Error c4err;
    if (error) {
        CBLLogInfo(WebSocket, @"CBLWebSocket CLOSED WITH ERROR: %@", error.my_compactDescription);
        convertError(error, &c4err);
    } else {
        CBLLogInfo(WebSocket, @"CBLWebSocket CLOSED");
        c4err = {};
    }
    [self c4SocketClosed: c4err];
}

- (void) c4SocketClosed: (C4Error)c4err {
    [self callC4Socket:^(C4Socket *socket) {
        c4socket_closed(socket, c4err);
    }];
}

#pragma mark - NSSTREAM SUPPORT:

- (SecTrustRef) copyTrustFromReadStream {
    return (SecTrustRef) CFReadStreamCopyProperty((CFReadStreamRef)_in,
                                                  kCFStreamPropertySSLPeerTrust);
}

- (BOOL) checkSSLCert {
    _checkSSLCert = false;
    
    SecTrustRef trust = [self copyTrustFromReadStream];
    Assert(trust);
    
    [self updateServerCertificateFromTrust: trust];

    NSURL* url = _logic.URL;
    auto check = [[CBLTrustCheck alloc] initWithTrust: trust
                                                 host: url.host
                                                 port: url.port.shortValue];
    CFRelease(trust);

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
        [self closeWithError: error];
        return false;
    } else
        CBLLogVerbose(WebSocket, @"TLS handshake succeeded");
    
    return true;
}

- (void) updateServerCertificateFromTrust: (SecTrustRef)trust {
    SecCertificateRef cert = NULL;
    if (trust != NULL) {
        if (SecTrustGetCertificateCount(trust) > 0)
            cert = SecTrustGetCertificateAtIndex(trust, 0);
        else
            CBLWarn(WebSocket, @"SecTrust has no certificates"); // Shouldn't happen
    }
    _replicator.serverCertificate = cert;
}

// Asynchronously sends data over the socket, and calls the completion handler block afterwards.
- (void) writeData: (NSData*)data completionHandler: (void (^)())completionHandler {
    _pendingWrites.emplace_back(data, completionHandler);
    if (_hasSpace)
        [self doWrite];
}

- (void) doWrite {
    if (_checkSSLCert && ![self checkSSLCert])
        return;
    
    while (!_pendingWrites.empty()) {
        auto &w = _pendingWrites.front();
        auto nBytes = [_out write: (const uint8_t*)w.data.bytes + w.bytesWritten
                        maxLength: w.data.length - w.bytesWritten];
        if (nBytes <= 0) {
            _hasSpace = false;
            return;
        }
        w.bytesWritten += nBytes;
        if (w.bytesWritten < w.data.length) {
            _hasSpace = false;
            return;
        }
        w.data = nil;
        if (w.completionHandler)
            w.completionHandler();
        _pendingWrites.erase(_pendingWrites.begin());
    }
}

- (void) doRead {
    CBLLogVerbose(WebSocket, @"DoRead...");
    Assert(_hasBytes);
    _hasBytes = false;
    while (_in.hasBytesAvailable) {
        if (self.readThrottled) {
            _hasBytes = true;
            break;
        }
        NSInteger nBytes = [_in read: _readBuffer maxLength: kReadBufferSize];
        CBLLogVerbose(WebSocket, @"DoRead read %zu bytes", nBytes);
        if (nBytes <= 0)
            break;
        if (!_gotResponseHeaders)
            [self receivedHTTPResponseBytes: _readBuffer length: nBytes];
        else
            [self receivedBytes: _readBuffer length: nBytes];
    }
}

- (void)stream: (NSStream*)stream handleEvent: (NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            CBLLogVerbose(WebSocket, @"%@: OpenCompleted on %@", self, stream);
            break;
        case NSStreamEventHasBytesAvailable:
            Assert(stream == _in);
            CBLLogVerbose(WebSocket, @"%@: HasBytesAvailable", self);
            if (_checkSSLCert && ![self checkSSLCert])
                break;
            _hasBytes = true;
            if (!self.readThrottled)
                [self doRead];
            break;
        case NSStreamEventHasSpaceAvailable:
            CBLLogVerbose(WebSocket, @"%@: HasSpaceAvailable", self);
            _hasSpace = true;
            [self doWrite];
            break;
        case NSStreamEventEndEncountered:
            CBLLogVerbose(WebSocket, @"%@: EndEncountered on %s stream",
                          self, ((stream == _out) ? "write" : "read"));
            [self closeWithError: nil];
            break;
        case NSStreamEventErrorOccurred:
            CBLLogVerbose(WebSocket, @"%@: ErrorEncountered on %@", self, stream);
            if (_checkSSLCert) {
                SecTrustRef trust = [self copyTrustFromReadStream];
                [self updateServerCertificateFromTrust:
                 (trust != NULL ? (SecTrustRef) CFAutorelease(trust) : NULL)];
            }
            [self closeWithError: stream.streamError];
            break;
        default:
            break;
    }
}

- (void) disconnect {
    CBLLogVerbose(WebSocket, @"%@: Disconnect", self);
    if (_in || _out) {
        _in.delegate = _out.delegate = nil;
        [_in close];
        [_out close];
        _in = nil;
        _out = nil;
        self.sockfd = -1; // NOTE: Socket was closed by the streams
    }
    
    if (_sockfd >= 0) {
        close(_sockfd);
        self.sockfd = -1;
    }
}

#pragma mark - Helper

+ (NSArray*) parseCookies: (NSString*) cookieStr {
    Assert(cookieStr.length > 0, @"Trtying to parse empty cookie string");
    
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
