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
#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#import <memory>
#import <netdb.h>

extern "C" {
#import "MYAnonymousIdentity.h"
#import "MYErrorUtils.h"
}

using namespace fleece;
using namespace fleeceapi;

static constexpr size_t kMaxReceivedBytesPending = 100 * 1024;
static constexpr NSTimeInterval kConnectTimeout = 15.0;

// The value should be greater than the heartbeat to avoid read/write timeout;
// the current default heartbeat is 300 sec:
static constexpr NSTimeInterval kIdleTimeout = 320.0;

@implementation CBLWebSocket
{
    AllocedDict _options;
    NSOperationQueue* _queue;
    dispatch_queue_t _c4Queue;
    NSURLSession* _session;
    NSURLSessionStreamTask *_task;
    NSString* _expectedAcceptHeader;
    CBLHTTPLogic* _logic;
    NSString* _clientCertID;
    C4Socket* _c4socket;
    NSError* _cancelError;
    BOOL _receiving;
    size_t _receivedBytesPending, _sentBytesPending;
    CFAbsoluteTime _lastReadTime;
    BOOL _requestedClose;
    BOOL _closeOnError;
}


+ (void) registerWithC4 {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        c4socket_registerFactory({
            .providesWebSockets = false,
            .open = &doOpen,
            .close = &doClose,
            .write = &doWrite,
            .completedReceive = &doCompletedReceive
        });
        CBLLog(WebSocket, @"CBLWebSocket registered as C4SocketFactory");
    });
}

static void doOpen(C4Socket* s, const C4Address* addr, C4Slice optionsFleece) {
    NSURLComponents* c = [NSURLComponents new];
    if (addr->scheme == "blips"_sl || addr->scheme == "wss"_sl)
        c.scheme = @"https";
    else
        c.scheme = @"http";
    c.host = slice2string(addr->hostname);
    c.port = @(addr->port);
    c.path = slice2string(addr->path);
    NSURL* url = c.URL;
    if (!url) {
        c4socket_closed(s, {LiteCoreDomain, kC4ErrorInvalidParameter});
        return;
    }
    auto socket = [[CBLWebSocket alloc] initWithURL: url c4socket: s options: optionsFleece];
    s->nativeHandle = (__bridge void*)socket;
    [socket start];
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


- (instancetype) initWithURL: (NSURL*)url c4socket: (C4Socket*)c4socket options: (slice)options {
    self = [super init];
    if (self) {
        _c4socket = c4socket;
        _options = AllocedDict(options);

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url];
        request.HTTPShouldHandleCookies = NO;
        _logic = [[CBLHTTPLogic alloc] initWithURLRequest: request];
        _logic.handleRedirects = YES;

        [self setupAuth];

        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 1;     // make it serial!
        _queue.name = [NSString stringWithFormat: @"WebSocket to %@:%u", url.host, _logic.port];

        _c4Queue = dispatch_queue_create("Websocket C4 dispatch", DISPATCH_QUEUE_SERIAL);

        NSURLSessionConfiguration* conf = [NSURLSessionConfiguration defaultSessionConfiguration];
        conf.HTTPShouldSetCookies = NO;
        conf.HTTPCookieStorage = nil;
        conf.URLCache = nil;
        _session = [NSURLSession sessionWithConfiguration: conf
                                                 delegate: self
                                            delegateQueue: _queue];
    }
    return self;
}


#if DEBUG
- (void)dealloc {
    CBLLogVerbose(WebSocket, @"DEALLOC CBLWebSocket");
}
#endif


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


#pragma mark - HANDSHAKE:


- (void) start {
    [_queue addOperationWithBlock: ^{
        [self _start];
    }];
}


- (void) _start {
    CBLLog(WebSocket, @"CBLWebSocket connecting to %@:%d...", _logic.URL.host, _logic.port);
    _cancelError = nil;

    // Configure the nonce/key for the request:
    uint8_t nonceBytes[16];
    (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(nonceBytes), nonceBytes);
    NSData* nonceData = [NSData dataWithBytes: nonceBytes length: sizeof(nonceBytes)];
    NSString* nonceKey = [nonceData base64EncodedStringWithOptions: 0];
    _expectedAcceptHeader = base64Digest([nonceKey stringByAppendingString:
                                          @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"]);

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

    _task = [_session streamTaskWithHostName: (NSString*)_logic.URL.host
                                        port: _logic.port];
    [_task resume];

    if (_logic.useTLS)
        [_task startSecureConnection];

    [_task writeData: _logic.HTTPRequestData timeout: kConnectTimeout
           completionHandler: ^(NSError* error) {
       CBLLogVerbose(WebSocket, @"CBLWebSocket Sent HTTP request...");
       if (![self checkError: error])
           [self readHTTPResponse];
   }];
}


- (void) readHTTPResponse {
    CFHTTPMessageRef httpResponse = CFHTTPMessageCreateEmpty(NULL, false);
    [_task readDataOfMinLength: 1 maxLength: NSUIntegerMax timeout: kConnectTimeout
             completionHandler: ^(NSData* data, BOOL atEOF, NSError* error)
    {
        CBLLogVerbose(WebSocket, @"Received %zu bytes of HTTP response", (size_t)data.length);
        if (error) {
            [self didCloseWithError: error];
            return;
        }
        if (!CFHTTPMessageAppendBytes(httpResponse, (const UInt8*)data.bytes, data.length)) {
            // Error reading response!
            [self didCloseWithCode: kWebSocketCloseProtocolError
                            reason: @"Unparseable HTTP response"];
            return;
        }
        if (CFHTTPMessageIsHeaderComplete(httpResponse)) {
            [self receivedHTTPResponse: httpResponse];
            CFRelease(httpResponse);
        } else {
            [self readHTTPResponse];        // wait for more data
        }
    }];
}


- (void) receivedHTTPResponse: (CFHTTPMessageRef)httpResponse {
    [_logic receivedResponse: httpResponse];
    NSInteger httpStatus = _logic.httpStatus;

    if (_logic.shouldRetry) {
        // Retry the connection, due to a redirect or auth challenge:
        [_task cancel];
        _task = nil;
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
    auto socket = _c4socket;
    dispatch_async(_c4Queue, ^{
        c4socket_gotHTTPResponse(socket, (int)httpStatus, {headersFleece.buf, headersFleece.size});
    });

    if (httpStatus != 101) {
        // Unexpected HTTP status:
        C4WebSocketCloseCode closeCode = kWebSocketClosePolicyError;
        if (httpStatus >= 300 && httpStatus < 1000)
            closeCode = (C4WebSocketCloseCode)httpStatus;
        NSString* reason = CFBridgingRelease(CFHTTPMessageCopyResponseStatusLine(httpResponse));
        [self didCloseWithCode: closeCode reason: reason];

    } else if (!checkHeader(headers, @"Connection", @"Upgrade", NO)) {
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Connection' header"];
    } else if (!checkHeader(headers, @"Upgrade", @"websocket", NO)) {
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Upgrade' header"];
    } else if (!checkHeader(headers, @"Sec-WebSocket-Accept", _expectedAcceptHeader, YES)) {
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Sec-WebSocket-Accept' header"];
    } else {
        // TODO: Check Sec-WebSocket-Extensions for unknown extensions
        // Now I can start the WebSocket protocol:
        [self connected: headers];
    }
}


- (void) connected: (NSDictionary*)responseHeaders {
    CBLLog(WebSocket, @"CBLWebSocket CONNECTED!");
    _lastReadTime = CFAbsoluteTimeGetCurrent();
    [self receive];
    auto socket = _c4socket;
    dispatch_async(_c4Queue, ^{
        c4socket_opened(socket);
    });
}


#pragma mark - READ / WRITE:


// callback from C4Socket
- (void) writeAndFree: (C4SliceResult) allocatedData {
    NSData* data = [NSData dataWithBytesNoCopy: (void*)allocatedData.buf
                                        length: allocatedData.size
                                  freeWhenDone: NO];
    CBLLogVerbose(WebSocket, @">>> sending %zu bytes...", allocatedData.size);
    [_queue addOperationWithBlock: ^{
        [self->_task writeData: data timeout: kIdleTimeout
             completionHandler: ^(NSError* error)
         {
             size_t size = allocatedData.size;
             c4slice_free(allocatedData);
             if (![self checkError: error]) {
                 CBLLogVerbose(WebSocket, @"    (...sent %zu bytes)", size);
                 auto socket = self->_c4socket;
                 dispatch_async(self->_c4Queue, ^{
                     c4socket_completedWrite(socket, size);
                 });
             }
         }];
    }];
}


- (void) receive {
    if(_receiving || !_task)
        return;
    _receiving = true;
    [_task readDataOfMinLength: 1 maxLength: NSUIntegerMax timeout: kIdleTimeout
             completionHandler: ^(NSData* data, BOOL atEOF, NSError* error)
    {
        self->_receiving = false;
        self->_lastReadTime = CFAbsoluteTimeGetCurrent();
        if (error)
            [self didCloseWithError: error];
        else {
            self->_receivedBytesPending += data.length;
            CBLLogVerbose(WebSocket, @"<<< received %zu bytes%s [now %zu pending]",
                          (size_t)data.length, (atEOF ? " (EOF)" : ""), self->_receivedBytesPending);
            if (data.length > 0) {
                auto socket = self->_c4socket;
                dispatch_async(self->_c4Queue, ^{
                    c4socket_received(socket, {data.bytes, data.length});
                });
                if (!atEOF && self->_receivedBytesPending < kMaxReceivedBytesPending)
                    [self receive];
            }
            if (atEOF && !_requestedClose) {
                // The peer has closed the socket, but I still have to close my side, else my
                // -readClosedForStreamTask:... delegate method won't be called:
                [self->_task closeRead];
            }
        }
    }];
}


// callback from C4Socket
- (void) completedReceive: (size_t)byteCount {
    [_queue addOperationWithBlock: ^{
        self->_receivedBytesPending -= byteCount;
        [self receive];
    }];
}


// callback from C4Socket
- (void) closeSocket {
    [_queue addOperationWithBlock: ^{
        CBLLog(WebSocket, @"CBLWebSocket closeSocket requested");
        _requestedClose = YES;
        [self->_task closeWrite];
        [self->_task closeRead];
    }];
}


#pragma mark - URL SESSION DELEGATE:


- (void) URLSession: (NSURLSession *)session
         didReceiveChallenge: (NSURLAuthenticationChallenge *)challenge
          completionHandler: (void (^)(NSURLSessionAuthChallengeDisposition,
                                       NSURLCredential *))completionHandler
{
    auto disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential* credential = nil;
    NSString* authMethod = challenge.protectionSpace.authenticationMethod;
    if ($equal(authMethod, NSURLAuthenticationMethodServerTrust)) {
        // Check server's SSL cert:
        auto check = [[CBLTrustCheck alloc] initWithChallenge: challenge];
        Value pin = _options[kC4ReplicatorOptionPinnedServerCert];
        if (pin) {
            check.pinnedCertData = slice(pin.asData()).copiedNSData();
            if (!check.pinnedCertData) {
                CBLWarn(WebSocket, @"Invalid value for replicator %s property (must be NSData)",
                     kC4ReplicatorOptionPinnedServerCert);
                completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
                return;
            }
        }

        NSError* error;
        credential = [check checkTrust: &error];
        if (credential) {
            CBLLog(WebSocket, @"    useCredential for trust: %@", credential);
            disposition = NSURLSessionAuthChallengeUseCredential;
        } else {
            _cancelError = error;
            CBLWarn(WebSocket, @"TLS handshake failed: %@: %@",
                 challenge.protectionSpace, error.localizedDescription);
            disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
        }

    } else if ($equal(authMethod, NSURLAuthenticationMethodClientCertificate)) {
        // Server is checking client cert:
        if (_clientCertID) {
            SecIdentityRef identity = MYFindIdentity(_clientCertID);
            if (identity) {
                credential = [NSURLCredential credentialWithIdentity: identity
                                                        certificates: @[]
                                                   persistence: NSURLCredentialPersistenceNone];
                disposition = NSURLSessionAuthChallengeUseCredential;
                CFRelease(identity);
            } else {
                CBLWarn(Sync, @"Can't find SecIdentityRef with id '%@'", _clientCertID);
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        }
    }

    completionHandler(disposition, credential);
}


- (void)URLSession:(NSURLSession *)session readClosedForStreamTask:(NSURLSessionStreamTask *)task
{
    [self streamClosed: NO];
}

- (void)URLSession:(NSURLSession *)session writeClosedForStreamTask:(NSURLSessionStreamTask *)task
{
    [self streamClosed: YES];
}

- (void) streamClosed: (BOOL)isWrite {
    BOOL expectedClose = _requestedClose || _closeOnError;
    CBLLog(WebSocket, @"CBLWebSocket %s stream closed%s",
           (isWrite ? "write" : "read"),
           (expectedClose ? "" : " unexpectedly"));
    if (!expectedClose) {
        _cancelError = MYError(ECONNRESET, NSPOSIXErrorDomain, @"Network connection lost");
        [_task cancel];
    }
}


- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
        didCompleteWithError:(nullable NSError *)error
{
    if (task == _task) {
        [self didCloseWithError: error];
    }
}


#pragma mark - ERROR HANDLING:


- (bool) checkError: (NSError*)error {
    if (!error)
        return false;
    [self didCloseWithError: error];
    return true;
}


- (void) didCloseWithCode: (C4WebSocketCloseCode)code reason: (NSString*)reason {
    if (code == kWebSocketCloseNormal) {
        [self didCloseWithError: nil];
        return;
    }

    if (!_task)
        return;
    
    [self closeTaskOnError];

    CBLLog(WebSocket, @"CBLWebSocket CLOSED WITH STATUS %d \"%@\"", (int)code, reason);
    nsstring_slice reasonSlice(reason);
    C4Error c4err = c4error_make(WebSocketDomain, code, reasonSlice);
    c4socket_closed(_c4socket, c4err);
}


- (void) didCloseWithError: (NSError*)error {
    if (!_task)
        return;
    
    if (error)
        [self closeTaskOnError];
    else
        _task = nil;

    // We sometimes get bogus(?) ENOTCONN errors after closing the socket.
    if (_requestedClose && [error my_hasDomain: NSPOSIXErrorDomain code: ENOTCONN]) {
        CBLLog(WebSocket, @"CBLWebSocket ignoring %@", error.my_compactDescription);
        error = nil;
    }

    C4Error c4err;
    if (error) {
        if ([error my_hasDomain: NSURLErrorDomain code: kCFURLErrorCancelled] && _cancelError != nil)
            error = _cancelError;
        CBLLog(WebSocket, @"CBLWebSocket CLOSED WITH ERROR: %@", error.my_compactDescription);
        convertError(error, &c4err);
    } else {
        CBLLog(WebSocket, @"CBLWebSocket CLOSED");
        c4err = {};
    }
    c4socket_closed(_c4socket, c4err);
}


// Workaround to ensure that the socket will be closed when an error occurs.
// From https://github.com/couchbase/couchbase-lite-ios/issues/2078,
// the socket might not be closed after getting the operation timed out error
// (Domain=NSPOSIXErrorDomain Code=60 "Operation timed out").
- (void) closeTaskOnError {
    _closeOnError = YES;
    [_task closeRead];
    [_task closeWrite];
    _task = nil;
}


#pragma mark - UTILITIES:


// Tests whether a header value matches the expected string.
static BOOL checkHeader(NSDictionary* headers, NSString* header, NSString* expected, BOOL caseSens) {
    NSString* value = headers[header];
    if (caseSens)
        return [value isEqualToString: expected];
    else
        return value && [value caseInsensitiveCompare: expected] == 0;
}


static NSString* base64Digest(NSString* string) {
    NSData* data = [string dataUsingEncoding: NSASCIIStringEncoding];
    unsigned char result[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([data bytes], (CC_LONG)[data length], result);
    data = [NSData dataWithBytes:result length:CC_SHA1_DIGEST_LENGTH];
    return [data base64EncodedStringWithOptions: 0];
}


@end
