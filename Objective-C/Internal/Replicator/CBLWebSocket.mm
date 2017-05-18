//
//  CBLWebSocket.m
//  StreamTaskTest
//
//  Created by Jens Alfke on 3/14/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLWebSocket.h"
#import "CBLHTTPLogic.h"
#import "CBLCoreBridge.h"
#import "c4Socket.h"
#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#import <memory>

using namespace fleece;
using namespace fleeceapi;

static constexpr size_t kMaxReceivedBytesPending = 100 * 1024;
static constexpr NSTimeInterval kConnectTimeout = 15.0;
static constexpr NSTimeInterval kIdleTimeout = 300.0;


@interface CBLWebSocket ()
@property (readwrite, atomic) NSString* protocol;
@end


@implementation CBLWebSocket
{
    AllocedDict _options;
    NSOperationQueue* _queue;
    dispatch_queue_t _c4Queue;
    NSURLSession* _session;
    NSURLSessionStreamTask *_task;
    NSString* _expectedAcceptHeader;
    NSArray* _protocols;
    CBLHTTPLogic* _logic;
    C4Socket* _c4socket;
    NSTimer* _pingTimer;
    BOOL _receiving;
    size_t _receivedBytesPending, _sentBytesPending;
    CFAbsoluteTime _lastReadTime;
}

@synthesize protocol=_protocol;


static C4LogDomain LogWS;
static bool sLogEnabled;

#define Log(FMT, ...) ({ if (sLogEnabled) c4log(LogWS, kC4LogInfo, FMT, ##__VA_ARGS__); })
#define LogVerbose(FMT, ...) ({ if (sLogEnabled) c4log(LogWS, kC4LogVerbose, FMT, ##__VA_ARGS__); })


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
        LogWS = c4log_getDomain("WS", true);
        sLogEnabled = c4log_getLevel(LogWS) <= kC4LogInfo;
        Log("CBLWebSocket registered as C4SocketFactory");
    });
}

static void doOpen(C4Socket* s, const C4Address* addr, FLSlice optionsFleece) {
    NSURLComponents* c = [NSURLComponents new];
    c.scheme = slice2string(addr->scheme);
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
        sLogEnabled = c4log_getLevel(LogWS) <= kC4LogInfo;

        _c4socket = c4socket;
        _options = AllocedDict(options);

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url];
        _logic = [[CBLHTTPLogic alloc] initWithURLRequest: request];
        _logic.handleRedirects = YES;

        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 1;     // make it serial!
        _queue.name = [NSString stringWithFormat: @"WebSocket to %@:%u", url.host, _logic.port];

        _c4Queue = dispatch_queue_create("Websocket C4 dispatch", DISPATCH_QUEUE_SERIAL);

        NSURLSessionConfiguration* conf = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration: conf
                                                 delegate: self
                                            delegateQueue: _queue];
    }
    return self;
}


#if DEBUG
- (void)dealloc {
    LogVerbose("DEALLOC CBLWebSocket");
}
#endif


#pragma mark - HANDSHAKE:


- (void) start {
    [_queue addOperationWithBlock: ^{
        [self _start];
    }];
}


- (void) _start {
    Log("CBLWebSocket connecting to %s:%hd...", _logic.URL.host.UTF8String, _logic.port);
    // Configure the nonce/key for the request:
    uint8_t nonceBytes[16];
    (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(nonceBytes), nonceBytes);
    NSData* nonceData = [NSData dataWithBytes: nonceBytes length: sizeof(nonceBytes)];
    NSString* nonceKey = [nonceData base64EncodedStringWithOptions: 0];
    _expectedAcceptHeader = base64Digest([nonceKey stringByAppendingString:
                                          @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"]);

    // Construct the HTTP request:
    for (Dict::iterator header(_options["headers"_sl].asDict()); header; ++header)
        _logic[slice2string(header.keyString())] = slice2string(header.value().asString());

    _logic[@"Connection"] = @"Upgrade";
    _logic[@"Upgrade"] = @"websocket";
    _logic[@"Sec-WebSocket-Version"] = @"13";
    _logic[@"Sec-WebSocket-Key"] = nonceKey;
    if (_protocols)
        _logic[@"Sec-WebSocket-Protocol"] = [_protocols componentsJoinedByString: @","];

    _task = [_session streamTaskWithHostName: (NSString*)_logic.URL.host
                                        port: _logic.port];
    [_task resume];

    if (_logic.useTLS)
        [_task startSecureConnection];

    [_task writeData: _logic.HTTPRequestData timeout: kConnectTimeout
           completionHandler: ^(NSError* error) {
       LogVerbose("CBLWebSocket Sent HTTP request...");
       if (![self checkError: error])
           [self readHTTPResponse];
   }];
}


- (void) readHTTPResponse {
    CFHTTPMessageRef httpResponse = CFHTTPMessageCreateEmpty(NULL, false);
    [_task readDataOfMinLength: 1 maxLength: NSUIntegerMax timeout: kConnectTimeout
             completionHandler: ^(NSData* data, BOOL atEOF, NSError* error)
    {
        LogVerbose("Received %zu bytes of HTTP response", data.length);
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
        self.protocol = headers[@"Sec-WebSocket-Protocol"];
        // TODO: Check Sec-WebSocket-Extensions for unknown extensions
        // Now I can start the WebSocket protocol:
        [self connected: headers];
    }
}


- (void) connected: (NSDictionary*)responseHeaders {
    Log("CBLWebSocket CONNECTED!");
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
    LogVerbose(">>> sending %zu bytes...", allocatedData.size);
    [_queue addOperationWithBlock: ^{
        [self->_task writeData: data timeout: kIdleTimeout
             completionHandler: ^(NSError* error)
         {
             size_t size = allocatedData.size;
             c4slice_free(allocatedData);
             if (![self checkError: error]) {
                 LogVerbose("    (...sent %zu bytes)", size);
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
            LogVerbose("<<< received %zu bytes%s [now %zu pending]", data.length, (atEOF ? " (EOF)" : ""), self->_receivedBytesPending);
            if (data) {
                auto socket = self->_c4socket;
                dispatch_async(self->_c4Queue, ^{
                    c4socket_received(socket, {data.bytes, data.length});
                });
                if (!atEOF && self->_receivedBytesPending < kMaxReceivedBytesPending)
                    [self receive];
            }
        }
    }];
}


- (void) completedReceive: (size_t)byteCount {
    [_queue addOperationWithBlock: ^{
        self->_receivedBytesPending -= byteCount;
        [self receive];
    }];
}


// callback from C4Socket
- (void) closeSocket {
    [_queue addOperationWithBlock: ^{
        Log("CBLWebSocket closeSocket requested");
        [self->_task closeWrite];
        [self->_task closeRead];
    }];
}


#pragma mark - URL SESSION DELEGATE:


#if DEBUG
- (void)URLSession:(NSURLSession *)session readClosedForStreamTask:(NSURLSessionStreamTask *)streamTask
{
    Log("CBLWebSocket read stream closed");
}


- (void)URLSession:(NSURLSession *)session writeClosedForStreamTask:(NSURLSessionStreamTask *)streamTask
{
    Log("CBLWebSocket write stream closed");
}
#endif


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
    NSError* error = nil;
    if (code != kWebSocketCloseNormal) {
        error = [NSError errorWithDomain: @"WebSocket"
                                    code: code
                                userInfo: @{NSLocalizedFailureReasonErrorKey: reason}];
    }
    [self didCloseWithError: error];
}

- (void) didCloseWithError: (NSError*)error {
    if (!_task)
        return;
    _task = nil;

    C4Error c4err = {};
    if (error) {
        //FIX: Better error mapping
        NSString* domain = error.domain;
        const char *message = error.localizedFailureReason.UTF8String;
        Log("CBLWebSocket CLOSED WITH ERROR: %s %ld \"%s\"", domain.UTF8String, (long)error.code, message);
        C4ErrorDomain c4Domain;
        auto c4Code = (int)error.code;
        if ([domain isEqualToString: NSPOSIXErrorDomain])
            c4Domain = POSIXDomain;
        else {
            c4Domain = LiteCoreDomain;
            c4Code = -1;
        }
        c4err = c4error_make(c4Domain, c4Code, c4str(message));
    } else {
        Log("CBLWebSocket CLOSED");
    }
    c4socket_closed(_c4socket, c4err);
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
