//
//  CBLAttachmentDownloader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/3/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLAttachmentDownloader.h"
#import "CBL_AttachmentTask.h"
#import "CBL_Attachment.h"
#import "CBL_BlobStoreWriter.h"
#import "CBLDatabase+Attachments.h"
#import "CBLStatus.h"
#import "CBLProgressGroup.h"
#import "CouchbaseLitePrivate.h"

#import "MYBlockUtils.h"
#import "MYURLUtils.h"
#import "MYZip.h"


#if DEBUG
#define TRANSIENT_FAILURES 1
#endif


@implementation CBLAttachmentDownloader
{
    NSURL* _url;
    CBLDatabase* _database;
    CBL_AttachmentTask* _task;
    CBL_BlobStoreWriter* _writer;
    NSError* _error;
}

#if TRANSIENT_FAILURES
BOOL CBLAttachmentDownloaderFakeTransientFailures;
@synthesize fakeTransientFailure=_fakeTransientFailure;
#endif


- (instancetype) initWithDbURL: (NSURL*)dbURL
                      database: (CBLDatabase*)database
                    attachment: (CBL_AttachmentTask*)task
                  onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    NSURL* url = [[dbURL URLByAppendingPathComponent: task.ID.docID]
                                        URLByAppendingPathComponent: task.ID.name];
    NSMutableString* urlStr = [url.absoluteString mutableCopy];
    if (task.ID.revID)
        [urlStr appendFormat: @"?rev=%@", task.ID.revID];
    self = [super initWithMethod: @"GET" URL: $url(urlStr) body: nil
                    onCompletion: onCompletion];
    if (self) {
        CBLProgressGroup* progress = task.progress;
        if ([database hasAttachmentWithDigest: task.ID.metadata[@"digest"]]) {
            // Already downloaded, so make the progress show completion:
            [progress finished];
            return nil;
        }

        _writer = task.writer;
        if (!_writer)
            _writer = task.writer = [database attachmentWriter];

        _database = database;
        _url = url;
        _task = task;

        __weak CBLAttachmentDownloader* weakSelf = self;
        progress.cancellationHandler = ^{
            [database doAsync: ^{
                [weakSelf stop];
            }];
        };
        if (progress.isCanceled) {
            return nil;
        }
#if TRANSIENT_FAILURES
        _fakeTransientFailure = CBLAttachmentDownloaderFakeTransientFailures;
#endif
    }
    return self;
}


- (void) addTask: (CBL_AttachmentTask*)otherTask {
    [_task.progress addProgressGroup: otherTask.progress];
}


- (NSURLSessionTask*) createTaskInURLSession:(NSURLSession *)session {
    [_writer openFile];

    uint64_t bytesRead = _writer.bytesWritten;
    NSString* eTag = _writer.eTag;
    if (bytesRead > 0) {
        if (_writer.eTag)
            [_request setValue: eTag forHTTPHeaderField: @"If-Match"];
        [_request setValue: $sprintf(@"bytes=%llu-", bytesRead) forHTTPHeaderField: @"Range"];
    }
    LogTo(RemoteRequest, @"%@: Headers = %@", self, _request.allHTTPHeaderFields);
    return [super createTaskInURLSession: session];
}


- (void) didReceiveResponse:(NSHTTPURLResponse *)response {
    [super didReceiveResponse: response];
    if (_status < 300) {
        BOOL reset = NO;
        // Check whether the server is honoring the "Range:" header:
        if (_writer.bytesWritten > 0 && (_status != 206 || !_responseHeaders[@"Content-Range"])) {
            LogTo(RemoteRequest, @"%@: Range header was not honored; restarting", self);
            reset = YES;
        }

        // Remember the eTag if the server supports resumeable downloads:
        _writer.eTag = _responseHeaders[@"Accept-Ranges"] ? _responseHeaders[@"Etag"] : nil;

        // Determine the content length:
        uint64_t contentLength = [_responseHeaders[@"Content-Length"] longLongValue];
        if (contentLength > 0) {
            contentLength += _writer.bytesWritten;
        } else {
            NSDictionary* meta = _task.ID.metadata;
            NSNumber* len = meta[@"encoded_length"] ?: meta[@"length"];
            contentLength = len ? len.longLongValue : UINT64_MAX;
        }
        _writer.contentLength = contentLength;
        if (reset)
            [_writer reset];
    }
}


- (void) didReceiveData:(NSData *)data {
#if TRANSIENT_FAILURES
    if (_fakeTransientFailure && _writer.bytesWritten > 0) {
        LogTo(RemoteRequest, @"%@: Fake transient failure at %llu bytes!", self, _writer.bytesWritten);
        _fakeTransientFailure = NO;
        NSError* error = [NSError errorWithDomain: NSURLErrorDomain
                                             code: NSURLErrorCannotConnectToHost userInfo: nil];
        [self didFailWithError: error];
        return;
    }
#endif
    [super didReceiveData: data];
    [_writer appendData: data];

}


- (void) didFinishLoading {
    [_writer finish];
    if ([_writer verifyDigest: _task.ID.metadata[@"digest"]]) {
        [_writer install];
        _writer = nil;
        CBL_AttachmentTask* task = _task;
        _task = nil; // so -clearConnection won't cancel it
        [self clearConnection];
        [self respondWithResult: task error: nil];
    } else {
        // digest didn't match:
        [self cancelWithStatus: kCBLStatusBadAttachment message: @"Attachment digest mismatch"];
    }
}


// overridden to close the writer, and delete the temp file if download is not resumeable
- (BOOL) retry {
    BOOL willRetry = [super retry];
    if (willRetry) {
        if (!_writer.eTag) {
            LogTo(RemoteRequest, @"%@: Will retry, but download isn't resumeable so truncating file", self);
            [_writer reset];
        }
        [_writer closeFile];
    }
    return willRetry;
}


// overridden to cancel + delete the task
- (void) clearConnection {
    [super clearConnection];
    [_writer cancel];
    _writer = nil;
}


@end
