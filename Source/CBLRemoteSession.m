//
//  CBLRemoteSession.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/4/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteSession.h"
#import "CBLRemoteRequest.h"
#import "CBL_ReplicatorSettings.h"
#import "CBLCookieStorage.h"
#import "CBLMisc.h"
#import "MYURLUtils.h"
#import "MYBlockUtils.h"

UsingLogDomain(Sync);


@interface CBLRemoteSession () <NSURLSessionDataDelegate>
@end


@implementation CBLRemoteSession
{
    NSURL* _baseURL;
    NSURLSession* _session;
    NSRunLoop* _runLoop;
    NSThread *_thread;
    id<CBLRemoteRequestDelegate> _requestDelegate;
    NSMutableDictionary<NSNumber*, CBLRemoteRequest*>* _requestIDs; // Used on operation queue only
    NSMutableSet<CBLRemoteRequest*>* _allRequests;                  // Used on API thread only
    CBLCookieStorage* _cookieStorage;
}

@synthesize authorizer=_authorizer;


+ (NSURLSessionConfiguration*) defaultConfiguration {
    NSURLSessionConfiguration* config;
    config = [[NSURLSessionConfiguration defaultSessionConfiguration] copy];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.URLCache = nil;
    config.HTTPAdditionalHeaders = @{@"User-Agent": [CBL_ReplicatorSettings userAgentHeader]};

    // Register the router's NSURLProtocol. This allows the replicator to access local databases
    // via their internalURLs.
    Class cblURLProtocol = NSClassFromString(@"CBL_URLProtocol");
    if (cblURLProtocol)
        config.protocolClasses = @[cblURLProtocol];
    return config;
}


- (instancetype)initWithConfiguration: (NSURLSessionConfiguration*)config
                              baseURL: (NSURL*)baseURL
                             delegate: (id<CBLRemoteRequestDelegate>)delegate
                           authorizer: (id<CBLAuthorizer>)authorizer
                        cookieStorage: (CBLCookieStorage*)cookieStorage
{
    self = [super init];
    if (self) {
        _baseURL = baseURL;
        _requestDelegate = delegate;
        _authorizer = authorizer;
        _cookieStorage = cookieStorage;
        NSOperationQueue* queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        _session = [NSURLSession sessionWithConfiguration: config
                                                 delegate: self
                                            delegateQueue: queue];
        _session.sessionDescription = @"Couchbase Lite";
        _runLoop = [NSRunLoop currentRunLoop];
        _thread = [NSThread currentThread];
        _requestIDs = [NSMutableDictionary new];
    }
    return self;
}


- (instancetype) initWithDelegate: (id<CBLRemoteRequestDelegate>)delegate {
    return [self initWithConfiguration: [[self class] defaultConfiguration]
                               baseURL: nil
                              delegate: delegate
                            authorizer: nil
                         cookieStorage: nil];
}


- (void)dealloc {
    if (_allRequests.count > 0)
        Warn(@"CBLRemoteSession dealloced but has leftover requests: %@", _allRequests);
}


- (void) close {
    [_session.delegateQueue addOperationWithBlock:^{
        // Do this on the queue so that it's properly ordered with the tasks being started in
        // the -startRequest method.
        LogTo(RemoteRequest, @"CBLRemoteSession closing");
        [_session finishTasksAndInvalidate];
    }];
}


- (void) startRequest: (CBLRemoteRequest*)request {
    request.session = self;
    request.delegate = _requestDelegate;
    if (_authorizer)
        request.authorizer = _authorizer;
    request.cookieStorage = _cookieStorage;
    NSURLSessionTask* task = [request createTaskInURLSession: _session];
    if (!task)
        return;

    if (!_allRequests)
        _allRequests = [NSMutableSet new];
    [_allRequests addObject: request];

    [_session.delegateQueue addOperationWithBlock:^{
        // Now running on delegate queue:
        _requestIDs[@(task.taskIdentifier)] = request;
        LogTo(RemoteRequest, @"CBLRemoteSession starting %@", request);
        [task resume]; // Go!
    }];
}


- (CBLRemoteJSONRequest*) startRequest: (NSString*)method
                                  path: (NSString*)path
                                  body: (id)body
                          onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    Assert(_baseURL);
    NSURL* url;
    if ([path hasPrefix: @"/"])
        url = [[NSURL URLWithString: path relativeToURL: _baseURL] absoluteURL];
    else
        url = CBLAppendToURL(_baseURL, path);
    LogVerbose(Sync, @"%@: %@ %@", self, method, url.my_sanitizedPath);
    CBLRemoteJSONRequest *req = [[CBLRemoteJSONRequest alloc] initWithMethod: method
                                                                         URL: url
                                                                        body: body
                                                                onCompletion: onCompletion];
    [self startRequest: req];
    return req;
}


- (NSArray<CBLRemoteRequest*>*) activeRequests {
    return _allRequests.allObjects;
}


- (void) stopActiveRequests {
    if (!_allRequests)
        return;
    LogTo(RemoteRequest, @"Stopping %u remote requests", (unsigned)_allRequests.count);
    // Clear _allRequests before iterating, to ensure that re-entrant calls to this won't
    // try to re-stop any of the requests. (Re-entrant calls are possible due to replicator
    // error handling when it receives the 'canceled' errors from the requests I'm stopping.)
    NSSet* requests = _allRequests;
    _allRequests = nil;
    [requests makeObjectsPerformSelector: @selector(stop)];
}


- (void) doAsync: (void (^)())block {
    MYOnThread(_thread, block);
}


#pragma mark - INTERNAL:


// must be called on the delegate queue
- (void) forgetTask: (NSURLSessionTask*)task {
    [_requestIDs removeObjectForKey: @(task.taskIdentifier)];
}


- (void) requestForTask: (NSURLSessionTask*)task
                     do: (void(^)(CBLRemoteRequest*))block
{
    // This is called on the delegate queue!
    Assert(task);
    CBLRemoteRequest *request = _requestIDs[@(task.taskIdentifier)];
    if (request) {
        LogDebug(RemoteRequest, @">>> performBlock for %@", request);
        [self doAsync: ^{
            // Now on the replicator thread
            LogDebug(RemoteRequest, @"   <<< calling block for %@", request);
            if (request.task == task) {
                block(request);
            } else {
                [_session.delegateQueue addOperationWithBlock:^{
                    [self forgetTask: task];
                }];
            }
        }];
    }
}


#pragma mark - SESSION DELEGATE:


// NOTE: All of these methods are called on the NSURLSession queue, not the replicator thread.


- (void) URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
    LogTo(RemoteRequest, @"CBLRemoteSession closed");
    if (_requestIDs.count > 0)
        Warn(@"CBLRemoteSession closed but has leftover tasks: %@", _requestIDs.allValues);
    _session = nil;
    _allRequests = nil;
    _requestIDs = nil;
}


- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)newURLRequest
        completionHandler:(void (^)(NSURLRequest * __nullable))completionHandler
{
    [self requestForTask: task do: ^(CBLRemoteRequest *request) {
        completionHandler([request willSendRequest: newURLRequest
                                  redirectResponse: response]);
    }];
}


- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                    NSURLCredential * __nullable credential))completionHandler
{
    [self requestForTask: task do: ^(CBLRemoteRequest *request) {
        NSURLSessionAuthChallengeDisposition disposition;
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        NSURLCredential* credential = nil;
        NSString* authMethod = challenge.protectionSpace.authenticationMethod;
        LogTo(RemoteRequest, @"Got challenge for %@: method=%@, err=%@",
              request, authMethod, challenge.error);
        if ($equal(authMethod, NSURLAuthenticationMethodHTTPBasic) ||
                $equal(authMethod, NSURLAuthenticationMethodHTTPDigest)) {
            // HTTP authentication:
            credential = [request credentialForHTTPAuthChallenge: challenge
                                                     disposition: &disposition];
        } else if ($equal(authMethod, NSURLAuthenticationMethodClientCertificate)) {
            // SSL client-cert authentication:
            credential = [request credentialForClientCertChallenge: challenge
                                                       disposition: &disposition];
        } else if ($equal(authMethod, NSURLAuthenticationMethodServerTrust)) {
            // Check server's SSL cert:
            SecTrustRef trust = [request checkServerTrust: challenge];
            if (trust) {
                credential = [NSURLCredential credentialForTrust: trust];
                disposition = NSURLSessionAuthChallengeUseCredential;
            } else {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            LogTo(RemoteRequest, @"    challenge: performDefaultHandling");
        }
        completionHandler(disposition, credential);
    }];
}


- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        needNewBodyStream:(void (^)(NSInputStream * __nullable bodyStream))completionHandler
{
    [self requestForTask: task do: ^(CBLRemoteRequest *request) {
        completionHandler([request needNewBodyStream]);
    }];
}

- (void)URLSession:(NSURLSession *)session
        dataTask:(NSURLSessionDataTask *)dataTask
        didReceiveResponse:(NSURLResponse *)response
        completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    [self requestForTask: dataTask do: ^(CBLRemoteRequest *request) {
        [request didReceiveResponse: (NSHTTPURLResponse*)response];

        // If the request had to change its credentials to pass authentication,
        // pick up the new authorizer for later requests:
        NSInteger status = ((NSHTTPURLResponse*)response).statusCode;
        id<CBLAuthorizer> auth = request.authorizer;
        if (auth && auth != _authorizer && status != 401) {
            LogTo(RemoteRequest, @"%@: Updated to %@", self, auth);
            _authorizer = auth;
        }

        completionHandler(request.running ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
    }];
}

- (void)URLSession:(NSURLSession *)session
        dataTask:(NSURLSessionDataTask *)dataTask
        didReceiveData:(NSData *)data
{
    [self requestForTask: dataTask do: ^(CBLRemoteRequest *request) {
        if (request.running)  // request might have just canceled itself
            [request _didReceiveData: data];
    }];
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didCompleteWithError:(nullable NSError *)error
{
    [self requestForTask: task do: ^(CBLRemoteRequest *request) {
        [_allRequests removeObject: request];
        if (error)
            [request didFailWithError: error];
        else
            [request _didFinishLoading];
    }];
    LogTo(RemoteRequest, @"CBLRemoteSession done with %@", _requestIDs[@(task.taskIdentifier)]);
    [self forgetTask: task];
}

- (void)URLSession:(NSURLSession *)session
        dataTask:(NSURLSessionDataTask *)dataTask
        willCacheResponse:(NSCachedURLResponse *)proposedResponse
        completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
    completionHandler(nil); // no caching
}


@end
