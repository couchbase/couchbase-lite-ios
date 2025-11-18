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
#import "fleece/Expert.hh"              // for AllocedDict
#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#import <memory>
#import <net/if.h>
#import <arpa/inet.h>
#import <vector>
#import "CollectionUtils.h"
#import "CBLURLEndpoint.h"
#import "CBLStringBytes.h"
#import <ifaddrs.h>
#import "CBLDNSService.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLCert.h"
#endif

extern "C" {
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

NSString * const kCBLWebSocketUseTLSServerAuthCallback = @"serverAuthCallback";

@interface CBLWebSocket () <NSStreamDelegate, DNSServiceDelegate>

// Socket descriptor for openning connection when a network interface is specified
@property (atomic) int sockfd;

@end

@implementation CBLWebSocket
{
    AllocedDict _options;
    dispatch_queue_t _queue;
    NSString* _expectedAcceptHeader;
    CBLHTTPLogic* _logic;
    C4Socket* _c4socket;
    CFHTTPMessageRef _httpResponse;
    id _keepMeAlive;
    
    NSInputStream* _in;
    NSOutputStream* _out;
    uint8_t* _readBuffer;
    std::vector<PendingWrite> _pendingWrites;
    
    bool _shouldCheckSSLCert;
    
    bool _hasBytes, _hasSpace;
    size_t _receivedBytesPending;
    bool _gotResponseHeaders;
    BOOL _connectingToProxy;
    BOOL _connectedThruProxy;
    
    __weak id<CBLWebSocketContext> __nullable _context;
    id<CBLCookieStore> __nullable _cookieStore;
    NSURL* __nullable _cookieURL;
    
    NSArray* _clientIdentity;
    
    BOOL _closing;
    
    NSString* _networkInterface;
    BOOL _useNetworkInterface;
    dispatch_queue_t _socketConnectQueue;
    
    CBLDNSService* _dnsService;
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
        
        id<CBLWebSocketContext> wsContext = (__bridge id<CBLWebSocketContext>)context;
        auto socket = [[CBLWebSocket alloc] initWithURL: url
                                               c4socket: s
                                                options: optionsFleece
                                                context: wsContext];
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
                     context: (nullable id<CBLWebSocketContext>)context {
    self = [super init];
    if (self) {
        _c4socket = c4socket;
        _options = AllocedDict(options);
        
        _context = context;
        _cookieStore = [context cookieStoreForWebsocket: self];
        _cookieURL = [context cookieURLForWebSocket: self];
        if (!_cookieURL) { _cookieURL = url; }
        
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
        _networkInterface = [context networkInterfaceForWebsocket: self];
        if (_networkInterface.length > 0) {
            queueName = [NSString stringWithFormat: @"%@-SocketConnect", queueName];
            _socketConnectQueue = dispatch_queue_create(queueName.UTF8String, DISPATCH_QUEUE_SERIAL);
            _useNetworkInterface = YES;
        }
    }
    return self;
}

- (void) dealloc {
    CBLLogVerbose(WebSocket, @"%@: DEALLOC...", self);
    Assert(!_in, @"Network stream was not closed");
    Assert(_sockfd < 0, @"Socket was not closed");
    free(_readBuffer);
    if (_httpResponse) {
        CFRelease(_httpResponse);
    }
}

- (void) dispose {
    CBLLogVerbose(WebSocket, @"%@: CBLWebSocket is being disposed", self);
    
    // This has to be done synchronously, because _c4socket will be freed when this method returns
    [self callC4Socket: ^(C4Socket *socket) {
        // A lock is necessary as the socket could be accessed from another thread under the dispatch
        // queue, otherwise crash will happen as the c4socket will be freed after this.
        // The c4socket doesn't call dispose under a mutex so this is safe from being deadlock.
        c4Socket_setNativeHandle(socket, nullptr);
        self->_c4socket = nullptr;
    }];

    dispatch_async(_queue, ^{
        // CBSE-16151:
        //
        // The CBLWebSocket may be called to dispose() by the c4socket before the
        // disconnect() can happen. For example, if the CBLWebSocket cannot
        // call c4socket_closed() callback before the timeout (5 seconds),
        // the c4socket will call to dispose() the CBLWebSocket right away.
        //
        // Therefore, before CBLWebSocket is dealloc, we need to ensure that the
        // disconnect() is called to close the network steams and sockets. This
        // needs to be done under the same queue that the network streams and
        // c4socket's handlers/callbacks are using to avoid threading issues.
        //
        // Note: the CBLWebSocket will be retained until this block is called
        // even though the _keepMeAlive is set to nil at the end of this
        // dispose method.
        if ([self isConnected]) {
            [self disconnect];
        }
    });
    
    // Remove the self-reference, so this object will be dealloced.
    self->_keepMeAlive = nil;
}

- (void) clearHTTPState {
    _gotResponseHeaders = _shouldCheckSSLCert = false;
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
                _clientIdentity = toSecIdentityWithCertChain(c4cert, &error);
                if (_clientIdentity) {
                    c4cert_release(c4cert);
                    return;
                }
                CBLWarnError(Sync, @"%@: Couldn't lookup the identity from the KeyChain: %@", self, error);
                c4cert_release(c4cert);
            } else {
                NSError* error;
                convertError(err, &error);
                CBLWarnError(Sync, @"%@: Couldn't create C4Cert from the certificate data: %@", self, error);
            }
        }
    }
#endif
    
    CBLWarn(Sync, @"%@: Unknown auth type or missing parameters for auth", self);
}

- (void) callC4Socket: (void (^)(C4Socket*))callback {
    @synchronized (self) {
        if (_c4socket) {
            callback(_c4socket);
        }
    }
}

#pragma mark - HANDSHAKE:

- (void) start {
    dispatch_async(_queue, ^{
        if (self->_logic.error) {
            // PAC resolution must have failed. Give up.
            [self closeWithError: self->_logic.error];
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
    
    if (_useNetworkInterface) {
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
        CBLLogInfo(WebSocket, @"%@: Connecting to HTTP proxy %@:%d...",
                   self, _logic.directHost, _logic.directPort);
        _logic.useProxyCONNECT = YES;
        [self writeData: _logic.HTTPRequestData completionHandler: nil];
    } else {
        CBLLogInfo(WebSocket, @"%@: Sending WebSocket request to %@:%d...", self, _logic.URL.host, _logic.port);
        [self _sendWebSocketRequest];
    }
}

- (void) connectToHostWithName: (NSString*)hostname
                          port: (NSInteger)port
              networkInterface: (NSString*)interface
{
    CBLLogInfo(WebSocket, @"%@: Connect to host '%@' port '%ld' interface '%@'",
               self, hostname, (long)port, interface);
    
    unsigned int index = if_nametoindex([interface cStringUsingEncoding: NSUTF8StringEncoding]);
    if (index == 0) {
        int errNo = errno;
        NSString* msg = $sprintf(@"Failed to find network interface %@ with errno %d", interface, errNo);
        CBLWarnError(WebSocket, @"%@: %@", self, msg);
        [self closeWithError: posixError(errNo, msg)];
        return;
    }
    CBLLogVerbose(WebSocket, @"%@: Interface '%@' is mapped to index '%u'", self, _networkInterface, index);
    
    _dnsService = [[CBLDNSService alloc] initWithHost: hostname
                                            interface: index
                                                 port: (UInt16)port
                                             delegate: self];
    [_dnsService start];
}

#pragma mark DNSServiceDelegate

- (void) didResolveSuccessWithAddress: (AddressInfo*)info {
    dispatch_async(_queue, ^{
        if (self->_dnsService) {
            CBLLogVerbose(WebSocket, @"%@: Host '%@' was resolved as ip=%@, family=%d",
                          self, info.host, info.addrstr, info.addr->sa_family);
            [self _socketConnect: info];
        }
    });
}

- (void) didResolveFailWithError: (NSError*)error {
    dispatch_async(_queue, ^{
        if (self->_dnsService) {
            CBLWarnError(WebSocket, @"%@: Host was failed to resolve with error '%@'",
                         self, error.my_compactDescription);
            [self closeWithError: error];
        }
    });
}

#pragma mark - Socket connect

- (void) _socketConnect: (AddressInfo*)info {
    Assert(_sockfd < 0);
    _sockfd = socket(info.addr->sa_family, SOCK_STREAM, 0);
    if (_sockfd < 0) {
        int errNo = errno;
        NSString* msg = $sprintf(@"Failed to create socket with errno %d (%@)", errNo, info);
        CBLWarnError(WebSocket, @"%@: %@", self, msg);
        [self closeWithError: posixError(errNo, msg)];
        return;
    }
    
    // Set network interface:
    Assert(info.interface > 0);
    
    UInt32 index = info.interface;
    int result = -1;
    if (info.addr->sa_family == AF_INET) {
        result = setsockopt(_sockfd, IPPROTO_IP, IP_BOUND_IF, &index, sizeof(index));
    } else if (info.addr->sa_family == AF_INET6 ){
        result = setsockopt(_sockfd, IPPROTO_IPV6, IPV6_BOUND_IF, &index, sizeof(index));
    }
    
    if (result < 0) {
        int errNo = errno;
        NSString* msg = $sprintf(@"Failed to set network interface %u with errno %d (%@)",
                                 (unsigned int)info.interface, errNo, info);
        CBLWarnError(WebSocket, @"%@: %@", self, msg);
        [self closeWithError: posixError(errNo, msg)];
        return;
    }
    
    CBLLogVerbose(WebSocket, @"%@: Successfully set network interface %u to socket option",
                  self, info.interface);
    
    // Connect:
    dispatch_async(_socketConnectQueue, ^{
        int sockfd = self.sockfd;
        if (sockfd < 0) {
            return; // Already disconnected
        }
        
        CBLLogVerbose(WebSocket, @"%@: Connect to IP address %@", self, info.addrstr);
        int status = connect(sockfd, info.addr, info.length);
        if (status == 0) {
            dispatch_async(self->_queue, ^{
                if (self->_sockfd < 0)
                    return; // Already disconnected
                
                // Enable non-blocking mode on the socket:
                int flags = fcntl(self->_sockfd, F_GETFL);
                if (fcntl(self->_sockfd, F_SETFL, flags | O_NONBLOCK) < 0) {
                    int errNo = errno;
                    NSString* msg = $sprintf(@"Failed to enable non-blocking mode with errno %d", errNo);
                    CBLWarnError(WebSocket, @"%@: %@", self, msg);
                    [self closeWithError: posixError(errNo, msg)];
                    return;
                }
                
                // Create a pair stream with the socket:
                CFReadStreamRef readStream;
                CFWriteStreamRef writeStream;
                CFStreamCreatePairWithSocket(kCFAllocatorDefault, self->_sockfd, &readStream, &writeStream);
                
                CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
                CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
                
                NSInputStream* input = CFBridgingRelease(readStream);
                NSOutputStream* output = CFBridgingRelease(writeStream);
                
                // Connect with the streams:
                [self _connectWithInputStream: input outputStream: output];
            });
        } else {
            int errNo = errno;
            NSString* msg = $sprintf(@"Failed to connect via the specified network interface %u with errno %d",
                                     info.interface, errNo);
            CBLWarnError(WebSocket, @"%@: %@", self, msg);
            NSError* error = posixError(errNo, msg);
            dispatch_async(self->_queue, ^{
                [self closeWithError: error];
            });
        }
    });
}

+ (nullable NSString*) getNetworkInterfaceName: (NSString*)name error: (NSError**)outError {
    const char *cName = [name UTF8String];
    sa_family_t inFamily = AF_UNSPEC; // input family
    unsigned char inIPBuf[sizeof(struct in6_addr)]; // input IP buffer
    
    // check for IPv4
    int s = inet_pton(AF_INET, cName, inIPBuf);
    if (s == 1) {
        inFamily = AF_INET;
    } else {
        CBLLogVerbose(WebSocket, @"%@: NI=%@ => inet_pton(%d) failed for IPv4. Looking for IPV6...",
                      self, name, s);
        
        // check for IPv6
        s = inet_pton(AF_INET6, cName, inIPBuf);
        if (s == 1) {
            inFamily = AF_INET6;
        } else {
            CBLLogVerbose(WebSocket, @"%@: NI=%@ => inet_pton(%d) failed for IPv6Address",
                          self, name, s);
        }
    }
    CBLLogVerbose(WebSocket, @"%@: Network interface(%@) isIP=%d, family=%d",
                  self, name, inFamily > AF_UNSPEC, inFamily);
    
    struct ifaddrs *ifaddrs;
    if ((getifaddrs(&ifaddrs) != 0)) {
        int errNo = errno;
        NSString* msg = $sprintf(@"Failed to find network interfaces with errno %d", errNo);
        if (outError) *outError = posixError(errNo, msg);
        return nil;
    }
    
    NSString* networkInterface = nil;
    for (struct ifaddrs *ifa = ifaddrs; ifa != NULL; ifa = ifa->ifa_next) {
        sockaddr* addr = ifa->ifa_addr;
        if (!addr)
            continue;
        
        int fam = ifa->ifa_addr->sa_family;
        if (inFamily > AF_UNSPEC) {
            if (inFamily == AF_INET && fam == AF_INET) {
                in_addr sa = ((sockaddr_in*)addr)->sin_addr;
                if (IN_ARE_ADDR_EQUAL(&sa, (in_addr*)inIPBuf)) {
                    networkInterface = [NSString stringWithUTF8String: ifa->ifa_name];
                    break;
                }
            } else if (inFamily == AF_INET6 && fam == AF_INET6) {
                /*
                 * With IPv6 address structures, assume a non-hostile implementation that
                 * stores the address as a contiguous sequence of bits. Any holes in the
                 * sequence would invalidate the use of memcmp().
                 * reference: https://opensource.apple.com/source/postfix/postfix-197/postfix/src/util/sock_addr.c
                 */
                in6_addr sa = ((sockaddr_in6*)addr)->sin6_addr;
                if (memcmp(&sa, (in6_addr*)inIPBuf, sizeof(in6_addr)) == 0) {
                    networkInterface = [NSString stringWithUTF8String: ifa->ifa_name];
                    break;
                }
            }
        } else if (strcmp(ifa->ifa_name, cName) == 0) {
            networkInterface = name;
            break;
        }
    }
    
    freeifaddrs(ifaddrs);
    
    return networkInterface;
}

static inline NSError* posixError(int errNo, NSString* msg) {
    return [NSError errorWithDomain: NSPOSIXErrorDomain
                               code: errNo
                           userInfo: @{NSLocalizedDescriptionKey : msg}];
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
    _shouldCheckSSLCert = false;
    
    if (_logic.useTLS) {
        CBLLogVerbose(WebSocket, @"%@: Enabling TLS...", self);
        
        _shouldCheckSSLCert = true;
        
        NSMutableDictionary* settings = [NSMutableDictionary dictionary];
        
        // Set the actual hostname used for certificate verification during the TLS handshake
        // when connecting through a proxy or a specified network interface. The hostname will
        // appear in the Server Name Indication (SNI) field of the TLS ClientHello message.
        if (_connectedThruProxy || _useNetworkInterface) {
            NSString* hostName = _logic.directHost;
            CBLLogVerbose(WebSocket, @"%@ Setting TLS peer (SNI) hostname: %@", self, hostName);
            [settings setObject: hostName forKey: (__bridge id)kCFStreamSSLPeerName];
        }
        
        // Disable the default certificate validation process using system's CA certs
        if ([self usesCustomTLSCertValidation]) {
            [settings setObject: @NO forKey: (__bridge id)kCFStreamSSLValidatesCertificateChain];
        }
        
        if (_clientIdentity) {
            [settings setObject: _clientIdentity forKey: (__bridge id)kCFStreamSSLCertificates];
        }
        
        if (![_in setProperty: settings forKey: (__bridge NSString*)kCFStreamPropertySSLSettings]) {
            CBLWarnError(WebSocket, @"%@: Failed to set SSL settings", self);
        }
        
        // When using client proxy, the stream will be reset after setting
        // the SSL properties. Make sure to update the _hasSpace flag to reflect
        // the current status of the stream.
        _hasSpace = _out.hasSpaceAvailable;
    }
}

- (BOOL) usesCustomTLSCertValidation {
    return (
            !!_options[kC4ReplicatorOptionPinnedServerCert]
#ifdef COUCHBASE_ENTERPRISE
            || _options[kC4ReplicatorOptionOnlySelfSignedServerCert].asBool()
            || _options[kC4ReplicatorOptionAcceptAllCerts].asBool()
#endif
    );
}

// Sends the initial WebSocket HTTP handshake request.
- (void) _sendWebSocketRequest {
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
    
    if (_cookieStore) {
        NSError* error = nil;
        NSString* cookie = [_cookieStore getCookies: _cookieURL error: &error];
        if (error) {
            CBLWarn(Sync, @"%@: Error while fetching cookies: %@", self, error);
            [self closeWithError: error];
            return;
        }
        
        if (cookie.length > 0)
            [cookies appendString: cookie];
        
        if (cookies.length > 0)
            [_logic setValue: cookies forHTTPHeaderField: @"Cookie"];
    }
    
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
    CBLLogVerbose(WebSocket, @"%@: Received %zu bytes of HTTP response", self, length);
    
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
    
    CBLLogInfo(WebSocket, @"%@: Proxy CONNECT to %@:%d...", self, _logic.URL.host, _logic.port);
    [self _sendWebSocketRequest];
}

// Handles the WebSocket handshake HTTP response.
- (void) receivedHTTPResponse: (CFHTTPMessageRef)httpResponse {
    // Post the response headers to LiteCore:
    NSDictionary *headers =  CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(httpResponse));
    NSString* cookie = headers[@"Set-Cookie"];
    if (cookie.length > 0) {
        if (_cookieStore) {
            NSArray* cookies = [CBLWebSocket parseCookies: cookie];
            
            // Save to LiteCore
            bool acceptParentDomain = _options[kC4ReplicatorOptionAcceptParentDomainCookies].asBool();
            for (NSString* cookieStr in cookies) {
                NSError* error;
                if (![_cookieStore saveCookie: cookieStr
                                          url: _cookieURL
                           acceptParentDomain: acceptParentDomain
                                        error: &error]) {
                    CBLWarn(WebSocket, @"%@: Cannot save cookie for URL %@ : %@",
                            self, _cookieURL.absoluteString, error.localizedDescription);
                }
            }
            
            if (cookies.count > 0) {
                NSMutableDictionary* newHeaders = [headers mutableCopy];
                newHeaders[@"Set-Cookie"] = cookies;
                headers = newHeaders;
            }
        } else {
            CBLWarn(WebSocket, @"%@: Received cookies but no cookie store is set", self);
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
    CBLLogInfo(WebSocket, @"%@: CBLWebSocket CONNECTED!", self);
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
    CBLLogVerbose(WebSocket, @"%@: >>> sending %zu bytes...", self, allocatedData.size);
    dispatch_async(_queue, ^{
        [self writeData: data completionHandler: ^() {
            size_t size = allocatedData.size;
            c4slice_free(allocatedData);
            CBLLogVerbose(WebSocket, @"%@:    (...sent %zu bytes)", self, size);
            [self callC4Socket:^(C4Socket *socket) {
                c4socket_completedWrite(socket, size);
            }];
        }];
    });
}

// Called when WebSocket data is received (NOT necessarily an entire message.)
- (void) receivedBytes: (const void*)bytes length: (size_t)length {
    self->_receivedBytesPending += length;
    CBLLogVerbose(WebSocket, @"%@: <<< received %zu bytes [now %zu pending]",
                  self, (size_t)length, self->_receivedBytesPending);
    [self callC4Socket:^(C4Socket *socket) {
        c4socket_received(socket, {bytes, length});
    }];
}

// callback from C4Socket
- (void) completedReceive: (size_t)byteCount {
    dispatch_async(_queue, ^{
        bool wasThrottled = self.readThrottled;
        self->_receivedBytesPending -= byteCount;
        if (self->_hasBytes && wasThrottled && !self.readThrottled)
            [self doRead];
    });
}

// callback from C4Socket
- (void) closeSocket {
    CBLLogInfo(WebSocket, @"%@: CBLWebSocket closeSocket requested", self);
    dispatch_async(_queue, ^{
        if ([self isConnected]) {
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
    
    CBLLogInfo(WebSocket, @"%@: CBLWebSocket CLOSING WITH STATUS %d \"%@\"", self, (int)code, reason);
    [self disconnect];
    nsstring_slice reasonSlice(reason);
    [self c4SocketClosed: c4error_make(WebSocketDomain, code, reasonSlice)];
}

// Closes the connection and passes the NSError (if any) to LiteCore.
- (void) closeWithError: (NSError*)error {
    // This function is always called from queue.
    if (_closing) {
        CBLLogVerbose(Sync, @"%@: Websocket is already closing. Ignoring the close.", self);
        return;
    }
    _closing = YES;
    
    [self disconnect];
    
    C4Error c4err;
    if (error) {
        CBLLogInfo(WebSocket, @"%@: CBLWebSocket CLOSED WITH ERROR: %@", self, error.my_compactDescription);
        convertError(error, &c4err);
    } else {
        CBLLogInfo(WebSocket, @"%@: CBLWebSocket CLOSED", self);
        c4err = {};
    }
    [self c4SocketClosed: c4err];
}

- (void) c4SocketClosed: (C4Error)c4err {
    [self callC4Socket:^(C4Socket *socket) {
        c4socket_closed(socket, c4err);
    }];
}

#pragma mark - TLS Support:

// Do not release trust from the read stream as it's not actually copied.
// The read stream will release the trust when it's being release.
- (SecTrustRef) getTrustFromReadStream {
    return (SecTrustRef) CFReadStreamCopyProperty((CFReadStreamRef)_in,
                                                  kCFStreamPropertySSLPeerTrust);
}

// Handles SSL certificate validation for the peer.
// Performs custom trust evaluation if enabled, notifies certificate to
// CBLWebSocketContext's callback and C4Socket and closes the connection on failure.
// Returns YES if the certificate is accepted.
- (BOOL) checkSSLCert {
    _shouldCheckSSLCert = NO;
    
    SecTrustRef trust = [self getTrustFromReadStream];
    Assert(trust);
    
    SecCertificateRef cert = [self certificateFromTrust: trust];
    [self notifyServerCertificateReceived: cert];
    
    NSError* error = nil;
    
    // Validate trust only when using custom certificate validation
    // (kCFStreamSSLValidatesCertificateChain is disabled).
    // If system validation is enabled, the certificates have already been verified,
    // and any validation failure will trigger NSStreamEventErrorOccurred without
    // calling this method.
    if ([self usesCustomTLSCertValidation]) {
        if (![self validateTrust: trust error: &error]) {
            [self closeWithError: error];
            return NO;
        }
    }
    
    NSData* certData = (NSData*) CFBridgingRelease(SecCertificateCopyData(cert));
    CFRelease(cert);
    
    // The hostname to open a socket to; proxy hostname, if a proxy is used.
    CBLStringBytes directHostName(_logic.directHost);
    
    if (!c4socket_gotPeerCertificate(_c4socket, data2slice(certData), directHostName)) {
        NSString* mesg = @"TLS handshake failed: certificate rejected by verification callback";
        CBLWarn(WebSocket, @"%@: %@", self, mesg);
        MYReturnError(&error, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain, @"%@", mesg);
        [self closeWithError: error];
        return NO;
    }
    
    CBLLogVerbose(WebSocket, @"%@: TLS handshake succeeded", self);
    return YES;
}

- (BOOL) validateTrust: (SecTrustRef)trust error: (NSError**)error {
#ifdef COUCHBASE_ENTERPRISE
    if (_options[kC4ReplicatorOptionAcceptAllCerts])
        return true;
#endif
    
    NSURL* url = _logic.URL;
    CBLTrustCheck* check = [[CBLTrustCheck alloc] initWithTrust: trust host: url.host port: url.port.shortValue];
    
    Value pinnedCert = _options[kC4ReplicatorOptionPinnedServerCert];
    if (pinnedCert) {
        check.pinnedCertData = slice(pinnedCert.asData()).copiedNSData();
    }
#ifdef COUCHBASE_ENTERPRISE
    else if (_options[kC4ReplicatorOptionOnlySelfSignedServerCert].asBool()) {
        check.acceptOnlySelfSignedCert = YES;
    }
#endif
    
    NSURLCredential* credentials = [check checkTrust: error];
    if (!credentials) {
        CBLWarn(WebSocket, @"%@: TLS handshake failed: certificate verification error: %@", self, (*error).localizedDescription);
        return false;
    }
    return true;
}

- (SecCertificateRef) certificateFromTrust: (SecTrustRef)trust {
    CFArrayRef certs = SecTrustCopyCertificateChain(trust);
    SecCertificateRef cert = (SecCertificateRef)CFArrayGetValueAtIndex(certs, 0);
    CFRetain(cert);
    CFRelease(certs);
    return cert;
}

- (void) notifyServerCertificateFromStream {
    SecTrustRef trust = [self getTrustFromReadStream];
    if (trust) {
        SecCertificateRef cert = [self certificateFromTrust: trust];
        [self notifyServerCertificateReceived: cert];
        CFRelease(cert);
    }
}

- (void) notifyServerCertificateReceived: (SecCertificateRef)cert {
    [_context webSocket: self didReceiveServerCert: cert];
}

#pragma mark - NSStream

// Asynchronously sends data over the socket, and calls the completion handler block afterwards.
- (void) writeData: (NSData*)data completionHandler: (void (^)())completionHandler {
    _pendingWrites.emplace_back(data, completionHandler);
    if (_hasSpace)
        [self doWrite];
}

- (void) doWrite {
    if (_shouldCheckSSLCert && ![self checkSSLCert])
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
    CBLLogVerbose(WebSocket, @"%@: DoRead...", self);
    Assert(_hasBytes);
    _hasBytes = false;
    while (_in.hasBytesAvailable) {
        if (self.readThrottled) {
            _hasBytes = true;
            break;
        }
        NSInteger nBytes = [_in read: _readBuffer maxLength: kReadBufferSize];
        CBLLogVerbose(WebSocket, @"%@: DoRead read %zu bytes", self, nBytes);
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
            CBLLogVerbose(WebSocket, @"%@: Open Completed on %@", self, stream);
            break;
        case NSStreamEventHasBytesAvailable:
            Assert(stream == _in);
            CBLLogVerbose(WebSocket, @"%@: HasBytesAvailable", self);
            if (_shouldCheckSSLCert && ![self checkSSLCert])
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
            CBLLogVerbose(WebSocket, @"%@: End Encountered on %s stream",
                          self, ((stream == _out) ? "write" : "read"));
            [self closeWithError: nil];
            break;
        case NSStreamEventErrorOccurred:
            CBLLogVerbose(WebSocket, @"%@: Error Encountered on %@", self, stream);
            if (_shouldCheckSSLCert) {
                [self notifyServerCertificateFromStream];
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
        NSInputStream* inStream = _in;
        NSOutputStream* outStream = _out;
        
        _in = nil;
        _out = nil;
        
        inStream.delegate = nil;
        outStream.delegate = nil;

        [inStream close];
        [outStream close];
        
        self.sockfd = -1; // NOTE: Socket was closed by the streams
    }
    
    if (_sockfd >= 0) {
        close(_sockfd);
        self.sockfd = -1;
    }
    
    if (_dnsService) {
        [_dnsService stop];
        _dnsService = nil;
    }
}

- (BOOL) isConnected {
    return (_in || _out || _sockfd >= 0 || _dnsService);
}

#pragma mark - Helper

+ (NSArray*) parseCookies: (NSString*) cookieStr {
    Assert(cookieStr.length > 0, @"%@: Trying to parse empty cookie string", self);
    
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
