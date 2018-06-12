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
#import "CBLLog.h"
#import "CBLReplicator+Internal.h"
#import "c4Socket.h"
#import "MYURLUtils.h"
#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#import <memory>
#import <netdb.h>
#import <vector>

extern "C" {
#import "MYAnonymousIdentity.h"
#import "MYErrorUtils.h"
}

using namespace fleece;
using namespace fleeceapi;

static constexpr size_t kReadBufferSize = 32 * 1024;

static constexpr size_t kMaxReceivedBytesPending = 100 * 1024;

static constexpr NSTimeInterval kConnectTimeout = 15.0;

// The value should be greater than the heartbeat to avoid read/write timeout;
// the current default heartbeat is 300 sec:
static constexpr NSTimeInterval kIdleTimeout = 320.0;


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
@end


@implementation CBLWebSocket
{
    AllocedDict _options;
    dispatch_queue_t _queue;
    NSString* _expectedAcceptHeader;
    CBLHTTPLogic* _logic;
    NSString* _clientCertID;
    std::atomic<C4Socket*> _c4socket;
    CFHTTPMessageRef _httpResponse;
    CFAbsoluteTime _lastReadTime;
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
    NSDictionary* _proxySettings;
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
        auto socket = [[CBLWebSocket alloc] initWithURL: url c4socket: s options: optionsFleece];
        s->nativeHandle = (__bridge void*)socket;
        socket->_keepMeAlive = socket;          // Prevents dealloc until doDispose is called
        [socket start];
    }
}

static void doClose(C4Socket* s) {
    [(__bridge CBLWebSocket*)s->nativeHandle closeSocket];
}

static void doWrite(C4Socket* s, C4SliceResult allocatedData) {
    [(__bridge CBLWebSocket*)s->nativeHandle writeAndFree: allocatedData];
}

static void doCompletedReceive(C4Socket* s, size_t byteCount) {
    [(__bridge CBLWebSocket*)s->nativeHandle completedReceive: byteCount];
}

static void doDispose(C4Socket* s) {
    [(__bridge CBLWebSocket*)s->nativeHandle dispose];
}


- (instancetype) initWithURL: (NSURL*)url c4socket: (C4Socket*)c4socket options: (slice)options {
    self = [super init];
    if (self) {
        _c4socket = c4socket;
        _options = AllocedDict(options);

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url];
        request.HTTPShouldHandleCookies = NO;
        _logic = [[CBLHTTPLogic alloc] initWithURLRequest: request];
        _logic.handleRedirects = YES;

        slice proxy = _options["HTTPProxy"_sl].asString();      //TODO: Add to c4Replicator.h
        if (proxy) {
            NSURL* proxyURL = [NSURL URLWithDataRepresentation: proxy.uncopiedNSData()
                                                 relativeToURL: nil];
            NSString* host = proxyURL.host;
            if ([proxyURL.scheme.lowercaseString hasPrefix: @"http"] && host) {
                _logic.proxySettings = @{(id)kCFProxyTypeKey:       (id)kCFProxyTypeHTTP,
                                         (id)kCFProxyHostNameKey:   host,
                                         (id)kCFProxyPortNumberKey: @(proxyURL.my_effectivePort)};
            } else {
                CBLWarn(Sync, @"Invalid replicator HTTPProxy setting <%.*s>",
                     (int)proxy.size, proxy.buf);
            }
        }
        _proxySettings = _logic.proxySettings;

        [self setupAuth];

        auto queueName = [NSString stringWithFormat: @"WebSocket to %@:%u",
                          url.host, _logic.port];
        _queue = dispatch_queue_create(queueName.UTF8String, DISPATCH_QUEUE_SERIAL);

        _readBuffer = (uint8_t*)malloc(kReadBufferSize);
    }
    return self;
}


- (void)dealloc {
    CBLLogVerbose(WebSocket, @"DEALLOC %@", self);
    Assert(!_in);
    free(_readBuffer);
    if (_httpResponse)
        CFRelease(_httpResponse);
}


- (void) dispose {
    CBLLogVerbose(WebSocket, @"C4Socket of %@ is being disposed", self);
    // This has to be done synchronously, because _c4socket will be freed when this method returns
    auto socket = _c4socket.exchange(nullptr);
    if (socket)
        socket->nativeHandle = nullptr;
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

    } else if ([authType isEqualToString: @ kC4AuthTypeClientCert]) {
        _clientCertID = slice2string(auth[kC4ReplicatorAuthClientCert].asString());
        if (_clientCertID)
            return;
    }

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
        [self _connect];
    });
}


// Opens the TCP connection.
// This may be called more than once if the initial HTTP response is a redirect or requires auth.
- (void) _connect {
    _hasBytes = _hasSpace = false;
    _pendingWrites.clear();
    [self clearHTTPState];

    _logic.proxySettings = _proxySettings;
    _logic.useProxyCONNECT = YES;
    _connectingToProxy = _logic.usingHTTPProxy;

    // Open the streams:
    NSInputStream *inStream;
    NSOutputStream *outStream;
    [NSStream getStreamsToHostWithName: _logic.directHost port: _logic.directPort
                           inputStream: &inStream outputStream: &outStream];
    _in = inStream;
    _out = outStream;
    CFReadStreamSetDispatchQueue((__bridge CFReadStreamRef)_in, _queue);
    CFWriteStreamSetDispatchQueue((__bridge CFWriteStreamRef)_out, _queue);
    _in.delegate = _out.delegate = self;
    [self configureTLS];
    [_in open];
    [_out open];

    if (_connectingToProxy) {
        CBLLog(WebSocket, @"%@ connecting to HTTP proxy %@:%d...",
               self, _logic.directHost, _logic.directPort);
        [self writeData: _logic.HTTPRequestData completionHandler: nil];
    } else {
        CBLLog(WebSocket, @"%@ connecting to %@:%d...", self, _logic.URL.host, _logic.port);
        [self _sendWebSocketRequest];
    }

    _lastReadTime = CFAbsoluteTimeGetCurrent();
    [self checkForTimeoutIn: kConnectTimeout];
}


// Sets the TLS/SSL settings of the streams, if necessary.
// This gets called again after connecting to a proxy, because the tunnel to the destination server
// may have its own TLS settings.
//FIX: What happens if the proxy connection and the destination both use TLS?
// Do we then have two layers of TLS? I don't think this will work... --jpa
- (void) configureTLS {
    _checkSSLCert = false;
    if (_logic.useTLS) {
        CBLLogVerbose(WebSocket, @"%@ enabling TLS", self);
        auto settings = CFDictionaryCreateMutable(nullptr, 0, nullptr, nullptr);
        if (_options[kC4ReplicatorOptionPinnedServerCert])
            CFDictionarySetValue(settings, kCFStreamSSLValidatesCertificateChain, kCFBooleanFalse);
        CFReadStreamSetProperty((__bridge CFReadStreamRef)_in,
                                kCFStreamPropertySSLSettings, settings);
        CFRelease(settings);
        _checkSSLCert = true;
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
    slice cookies = _options[kC4ReplicatorOptionCookies].asString();
    if (cookies)
        [_logic addValue: cookies.asNSString() forHTTPHeaderField: @"Cookie"];

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
        if (_connectingToProxy)
            [self receivedProxyHTTPResponse: httpResponse];
        else
            [self receivedHTTPResponse: httpResponse];
        CFRelease(httpResponse);
    }
}


// Handles a proxy HTTP response, triggering the WebSocket handshake if the tunnel is open.
- (void) receivedProxyHTTPResponse: (CFHTTPMessageRef)httpResponse {
    [_logic receivedResponse: httpResponse];
    NSInteger httpStatus = _logic.httpStatus;
    if (httpStatus != 200) {
        [self closeWithCode: (C4WebSocketCloseCode)httpStatus
                        reason: $sprintf(@"Proxy: %@", _logic.httpStatusMessage)];
        return;
    }

    // Now send the actual WebSocket GET request, over the open stream:
    _connectingToProxy = NO;
    _logic.proxySettings = nil;
    _logic.useProxyCONNECT = NO;
    [self clearHTTPState];
    [self configureTLS];

    CBLLog(WebSocket, @"%@ Proxy CONNECT to %@:%d...", self, _logic.URL.host, _logic.port);
    [self _sendWebSocketRequest];
}


// Handles the WebSocket handshake HTTP response.
- (void) receivedHTTPResponse: (CFHTTPMessageRef)httpResponse {
    [_logic receivedResponse: httpResponse];
    NSInteger httpStatus = _logic.httpStatus;

    if (_logic.shouldRetry) {
        // Retry the connection, due to a redirect or auth challenge:
        [self disconnect];
        [self start];
        return;
    }

    // Post the response headers to LiteCore:
    NSDictionary *headers =  CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(httpResponse));
    NSString* cookie = headers[@"Set-Cookie"];
    if ([cookie containsString: @", "]) {
        // CFHTTPMessage incorrectly merges multiple Set-Cookie headers. Undo that:
        NSMutableDictionary* newHeaders = [headers mutableCopy];
        newHeaders[@"Set-Cookie"] = [cookie componentsSeparatedByString: @", "];
        headers = newHeaders;
    }
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
    CBLLog(WebSocket, @"CBLWebSocket CONNECTED!");
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
    CBLLog(WebSocket, @"CBLWebSocket closeSocket requested");
    dispatch_async(_queue, ^{
        if (_in || _out) {
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

    CBLLog(WebSocket, @"CBLWebSocket CLOSING WITH STATUS %d \"%@\"", (int)code, reason);
    [self disconnect];
    nsstring_slice reasonSlice(reason);
    [self c4SocketClosed: c4error_make(WebSocketDomain, code, reasonSlice)];
}


// Closes the connection and passes the NSError (if any) to LiteCore.
- (void) closeWithError: (NSError*)error {
    [self disconnect];

    C4Error c4err;
    if (error) {
        CBLLog(WebSocket, @"CBLWebSocket CLOSED WITH ERROR: %@", error.my_compactDescription);
        convertError(error, &c4err);
    } else {
        CBLLog(WebSocket, @"CBLWebSocket CLOSED");
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


- (BOOL) checkSSLCert {
    SecTrustRef sslTrust = (SecTrustRef) CFReadStreamCopyProperty((CFReadStreamRef)_in,
                                                                  kCFStreamPropertySSLPeerTrust);
    Assert(sslTrust);
    _checkSSLCert = false;

    NSURL* url = _logic.URL;
    auto check = [[CBLTrustCheck alloc] initWithTrust: sslTrust
                                                 host: url.host port: url.port.shortValue];
    CFRelease(sslTrust);
    Value pin = _options[kC4ReplicatorOptionPinnedServerCert];
    if (pin) {
        check.pinnedCertData = slice(pin.asData()).copiedNSData();
        Assert(check.pinnedCertData, @"Invalid value for replicator %s property (must be NSData)",
               kC4ReplicatorOptionPinnedServerCert);
    }

    NSError* error;
    if (![check checkTrust: &error]) {
        CBLWarn(WebSocket, @"TLS handshake failed: %@", error.localizedDescription);
        [self closeWithError: error];
        return false;
    } else {
        CBLLogVerbose(WebSocket, @"TLS handshake succeeded");
    }
    return true;
}


// Asynchronously sends data over the socket, and calls the completion handler block afterwards.
- (void) writeData: (NSData*)data completionHandler: (void (^)())completionHandler {
    _pendingWrites.emplace_back(data, completionHandler);
    if (_hasSpace)
        [self doWrite];
}


- (void) doWrite {
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
    _lastReadTime = CFAbsoluteTimeGetCurrent();
    Assert(_hasBytes);
    _hasBytes = false;
    while (_in.hasBytesAvailable) {
        if (self.readThrottled) {
            _hasBytes = true;
            break;
        }
        size_t nBytes = [_in read: _readBuffer maxLength: kReadBufferSize];
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
            if (_checkSSLCert && ![self checkSSLCert])
                break;
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
            [self closeWithError: stream.streamError];
            break;
        default:
            break;
    }
}


- (void) checkForTimeoutIn: (NSTimeInterval)interval {
    interval += 1.0; // sometimes the timer goes off early
    CBLLogVerbose(WebSocket, @"%@: Checking for timeout in %.3f sec", self, interval);
    __weak CBLWebSocket* weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), _queue, ^{
        [weakSelf checkForTimeout];
    });
}


- (void) checkForTimeout {
    if (!_in)
        return;
    NSTimeInterval idleTime = CFAbsoluteTimeGetCurrent() - _lastReadTime;
    NSTimeInterval timeout = _gotResponseHeaders ? kIdleTimeout : kConnectTimeout;
    if (idleTime < timeout) {
        [self checkForTimeoutIn: timeout - idleTime];
    } else {
        [self closeWithError: MYError(NSURLErrorTimedOut, NSURLErrorDomain,
                                      @"Connection timed out")];
    }
}


- (void) disconnect {
    CBLLogVerbose(WebSocket, @"%@: Disconnect", self);
    _in.delegate = _out.delegate = nil;
    [_in close];
    [_out close];
    _in = nil;
    _out = nil;
}


@end
