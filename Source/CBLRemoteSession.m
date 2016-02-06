//
//  CBLRemoteSession.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/4/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteSession.h"
#import "CBLRemoteRequest.h"


@interface CBLRemoteSession () <NSURLSessionDataDelegate>
@end


@implementation CBLRemoteSession
{
    NSURLSession* _session;
    NSRunLoop* _runLoop;
    NSMutableDictionary* _requestIDs;  // taskIdentifier -> CBLRemoteRequest. Used on op-queue only
}


- (instancetype)initWithConfiguration: (NSURLSessionConfiguration*)config {
    self = [super init];
    if (self) {
        NSOperationQueue* queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        _session = [NSURLSession sessionWithConfiguration: config
                                                 delegate: self
                                            delegateQueue: queue];
        _session.sessionDescription = @"Couchbase Lite";
        _runLoop = [NSRunLoop currentRunLoop];
        _requestIDs = [NSMutableDictionary new];
    }
    return self;
}


- (instancetype)init {
    return [self initWithConfiguration: [NSURLSessionConfiguration defaultSessionConfiguration]];
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
    NSURLSessionTask* task = [request createTaskInURLSession: _session];
    if (!task)
        return;
    [_session.delegateQueue addOperationWithBlock:^{
        // Now running on delegate queue:
        _requestIDs[@(task.taskIdentifier)] = request;
        LogTo(RemoteRequest, @"CBLRemoteSession starting %@", request);
        [task resume]; // Go!
    }];
}


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
        //LogTo(RemoteRequest, @">>> performBlock for %@", request);
        CFRunLoopPerformBlock(_runLoop.getCFRunLoop, kCFRunLoopDefaultMode, ^{
            // Now on the replicator thread
            //LogTo(RemoteRequest, @"   <<< calling block for %@", request);
            if (request.task == task) {
                block(request);
            } else {
                [_session.delegateQueue addOperationWithBlock:^{
                    [self forgetTask: task];
                }];
            }
        });
        CFRunLoopWakeUp(_runLoop.getCFRunLoop);
    } else {
        Warn(@"CBLRemoteSession: Unknown task with ID %zu: %@", task.taskIdentifier, task);
    }
}


#pragma mark - SESSION DELEGATE:


// NOTE: All of these methods are called on the NSURLSession queue, not the replicator thread.


- (void) URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
    LogTo(RemoteRequest, @"CBLRemoteSession closed");
    if (_requestIDs.count > 0)
        Warn(@"CBLRemoteSession closed but has leftover tasks: %@", _requestIDs.allValues);
    _session = nil;
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
        [request didReceiveChallenge: challenge completionHandler: completionHandler];
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
        task:(NSURLSessionTask *)task
        didCompleteWithError:(nullable NSError *)error
{
    [self requestForTask: task do: ^(CBLRemoteRequest *request) {
        if (error)
            [request didFailWithError: error];
        else
            [request didFinishLoading];
    }];
    LogTo(RemoteRequest, @"CBLRemoteSession done with %@", _requestIDs[@(task.taskIdentifier)]);
    [self forgetTask: task];
}

- (void)URLSession:(NSURLSession *)session
        dataTask:(NSURLSessionDataTask *)dataTask
        didReceiveResponse:(NSURLResponse *)response
        completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    [self requestForTask: dataTask do: ^(CBLRemoteRequest *request) {
        [request didReceiveResponse: response];
        completionHandler(request.running ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
    }];
}

- (void)URLSession:(NSURLSession *)session
        dataTask:(NSURLSessionDataTask *)dataTask
        didReceiveData:(NSData *)data
{
    [self requestForTask: dataTask do: ^(CBLRemoteRequest *request) {
        if (request.running)  // request might have just canceled itself
            [request didReceiveData: data];
    }];
}

- (void)URLSession:(NSURLSession *)session
        dataTask:(NSURLSessionDataTask *)dataTask
        willCacheResponse:(NSCachedURLResponse *)proposedResponse
        completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
    completionHandler(nil); // no caching
}


@end
