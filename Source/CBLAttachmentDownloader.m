//
//  CBLAttachmentDownloader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/3/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLAttachmentDownloader.h"
#import "CBL_Attachment.h"
#import "CBL_BlobStoreWriter.h"
#import "CBLDatabase+Attachments.h"
#import "CBLStatus.h"
#import "CBL_Replicator.h"
#import "CouchbaseLitePrivate.h"

#import "MYBlockUtils.h"
#import "MYURLUtils.h"
#import "MYZip.h"


#define kProgressInterval 0.25


@implementation CBLAttachmentDownloader
{
    NSURL* _url;
    CBLDatabase* _database;
    CBL_AttachmentRequest* _attachment;
    NSMutableArray* _progresses;
    CBL_BlobStoreWriter* _writer;
    BOOL _resumeable;
    NSString* _eTag;
    uint64_t _bytesRead, _contentLength;
    NSError* _error;
    void (^_noteProgress)();
}

#if DEBUG
BOOL CBLAttachmentDownloaderFakeTransientFailures;
@synthesize fakeTransientFailure=_fakeTransientFailure;
#endif


- (instancetype) initWithDbURL: (NSURL*)dbURL
                      database: (CBLDatabase*)database
                    attachment: (CBL_AttachmentRequest*)attachment
                      progress: (NSProgress*)progress
                  onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    NSURL* url = [[dbURL URLByAppendingPathComponent: attachment.docID]
                                        URLByAppendingPathComponent: attachment.name];
    NSMutableString* urlStr = [url.absoluteString mutableCopy];
    if (attachment.revID)
        [urlStr appendFormat: @"?rev=%@", attachment.revID];
    self = [super initWithMethod: @"GET" URL: $url(urlStr) body: nil
                  requestHeaders: nil
                    onCompletion: onCompletion];
    if (self) {
        if ([database hasAttachmentWithDigest: attachment.metadata[@"digest"]]) {
            // Already downloaded, so make the progress show completion:
            progress.completedUnitCount = progress.totalUnitCount = 1;
            return nil;
        }
        _database = database;
        _url = url;
        _progresses = [NSMutableArray arrayWithObject: progress];
        [self addProgress: progress];
        if (progress.isCancelled)
            return nil;     // client already canceled, so give up

        _attachment = attachment;
        _writer = [database attachmentWriter];
        _writer.name = attachment.name;
        _noteProgress = MYThrottledBlock(kProgressInterval, ^{
            for (NSProgress* progress in _progresses)
                progress.completedUnitCount = MIN(_bytesRead, _contentLength-1);
        });
#if DEBUG
        _fakeTransientFailure = CBLAttachmentDownloaderFakeTransientFailures;
#endif
    }
    return self;
}


- (void) addProgress:(NSProgress *)progress {
    __weak CBLAttachmentDownloader* weakSelf = self;
    __weak NSProgress* weakProgress = progress;
    progress.cancellationHandler = ^{
        [weakSelf removeProgress: weakProgress];
    };
    if (progress.isCancelled)
        return; // progress was canceled, don't need to do anything with it

    NSProgress* current = _progresses.firstObject;
    [_progresses addObject: progress];
    [progress setUserInfoObject: _url forKey: NSProgressFileURLKey];
    if (current) {
        progress.completedUnitCount = current.completedUnitCount;
        progress.totalUnitCount = current.totalUnitCount;
    }
}

// This method can be called from any thread (via NSProgress cancellationHandlers)
- (void) removeProgress: (NSProgress*)progress {
    if (!progress)
        return;
    [_database doAsync: ^{
        if (_progresses.count == 1)
            [self cancelWithStatus: kCBLStatusCanceled];    // stop when last progress removed
        [_progresses removeObject: progress];
    }];
}


- (void) start {
    for (NSProgress* progress in _progresses)
        [progress setUserInfoObject: nil forKey: kCBLProgressError];

    if (_bytesRead > 0 && _eTag)
        [_request setValue: _eTag forHTTPHeaderField: @"If-Match"];
    [_request setValue: $sprintf(@"bytes=%llu-", _bytesRead) forHTTPHeaderField: @"Range"];
    LogTo(RemoteRequest, @"%@: Headers = %@", self, _request.allHTTPHeaderFields);
    [super start];
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    CBLStatus status = (CBLStatus) ((NSHTTPURLResponse*)response).statusCode;
    if (status < 300) {
        NSDictionary* headers = ((NSHTTPURLResponse*)response).allHeaderFields;
        [_writer openFile];
        // Check whether the server is honoring the "Range:" header:
        _bytesRead = _writer.length;
        if (_bytesRead > 0 && (status != 206 || !headers[@"Content-Range"])) {
            LogTo(RemoteRequest, @"%@: Range header was not honored; restarting", self);
            [_writer reset];
            _bytesRead = 0;
        }

        _eTag = headers[@"Etag"];
        _resumeable = _eTag != nil && headers[@"Accept-Ranges"] != nil;

        // Determine the number of bytes left:
        _contentLength = [headers[@"Content-Length"] longLongValue];
        if (_contentLength > 0) {
            _contentLength += _bytesRead;
        } else {
            NSDictionary* meta = _attachment.metadata;
            NSNumber* len = meta[@"encoded_length"] ?: meta[@"length"];
            _contentLength = len ? len.longLongValue : UINT64_MAX;
        }
        for (NSProgress* progress in _progresses) {
            progress.completedUnitCount = _bytesRead;
            progress.totalUnitCount = _contentLength;
        }
    }
    [super connection: connection didReceiveResponse: response];
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
#if DEBUG
    if (_fakeTransientFailure && _bytesRead > 0) {
        LogTo(RemoteRequest, @"%@: Fake transient failure at %llu bytes!", self, _bytesRead);
        _fakeTransientFailure = NO;
        NSError* error = [NSError errorWithDomain: NSURLErrorDomain
                                             code: NSURLErrorCannotConnectToHost userInfo: nil];
        [self connection: connection didFailWithError: error];
        [connection cancel];
        return;
    }
#endif
    [super connection: connection didReceiveData: data];
    [_writer appendData: data];
    _bytesRead += data.length;
    _noteProgress();

}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    CBL_BlobStoreWriter* writer = _writer;
    [writer finish];
    if ([writer verifyDigest: _attachment.metadata[@"digest"]]) {
        [_writer install];
        _writer = nil; // stop clearConnection from canceling
        [self clearConnection];
        for (NSProgress* progress in _progresses)
            progress.completedUnitCount = _contentLength;
        [self respondWithResult: writer error: nil];
    } else {
        [self cancelWithStatus: kCBLStatusBadAttachment];
    }
}


- (void) respondWithResult: (id)result error: (NSError*)error {
    if (error) {
        for (NSProgress* progress in _progresses)
        [progress setUserInfoObject: error forKey: kCBLProgressError];
    }
    [super respondWithResult: result error: error];
}


// overridden to close the writer, and delete the temp file if download is not resumeable
- (BOOL) retry {
    BOOL willRetry = [super retry];
    if (willRetry) {
        if (!_resumeable) {
            LogTo(RemoteRequest, @"%@: Will retry, but download isn't resumeable so truncating file", self);
            [_writer reset];
            _bytesRead = 0;
            for (NSProgress* progress in _progresses)
                progress.completedUnitCount = _bytesRead;
        }
        [_writer closeFile];
    }
    return willRetry;
}


// overridden to cancel + delete the writer
- (void) clearConnection {
    [super clearConnection];
    [_writer cancel];
    _writer = nil;
}


@end
