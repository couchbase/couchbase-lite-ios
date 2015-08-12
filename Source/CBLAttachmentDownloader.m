//
//  CBLAttachmentDownloader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/3/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLAttachmentDownloader.h"
#import "CBL_Attachment.h"
#import "CBL_BlobStore.h"
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
    NSDictionary* _metadata;
    NSProgress* _progress;
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
                      document: (NSDictionary*)doc
                attachmentName: (NSString*)name
                      progress: (NSProgress*)progress
                  onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    NSURL* url = [[dbURL URLByAppendingPathComponent: doc.cbl_id] URLByAppendingPathComponent: name];
    NSMutableString* urlStr = [url.absoluteString mutableCopy];
    [urlStr appendFormat: @"?rev=%@", doc.cbl_rev];
    self = [super initWithMethod: @"GET" URL: $url(urlStr) body: nil
                  requestHeaders: nil
                    onCompletion: onCompletion];
    if (self) {
        _progress = progress;
        [_progress setUserInfoObject: url forKey: NSProgressFileURLKey];
        __weak CBLAttachmentDownloader* weakSelf = self;
        _progress.cancellationHandler = ^{
            [database doAsync:^{
                [weakSelf cancelWithStatus: kCBLStatusCanceled];
            }];
        };
        if (_progress.isCancelled)
            return nil;     // client already canceled, so give up

        _metadata = [doc.cbl_attachments[name] copy];
        _writer = [database attachmentWriter];
        _writer.name = name;
        _noteProgress = MYThrottledBlock(kProgressInterval, ^{
            progress.completedUnitCount = MIN(_bytesRead, _contentLength-1);
        });
#if DEBUG
        _fakeTransientFailure = CBLAttachmentDownloaderFakeTransientFailures;
#endif
    }
    return self;
}


- (void) start {
    [_progress setUserInfoObject: nil forKey: kCBLProgressError];

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
            NSNumber* len = _metadata[@"encoded_length"] ?: _metadata[@"length"];
            _contentLength = len ? len.longLongValue : UINT64_MAX;
        }
        _progress.completedUnitCount = _bytesRead;
        _progress.totalUnitCount = _contentLength;
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
    if ([writer verifyDigest: _metadata[@"digest"]]) {
        [_writer install];
        _writer = nil; // stop clearConnection from canceling
        [self clearConnection];
        _progress.completedUnitCount = _contentLength;
        [self respondWithResult: writer error: nil];
    } else {
        [self cancelWithStatus: kCBLStatusBadAttachment];
    }
}


- (void) respondWithResult: (id)result error: (NSError*)error {
    if (error)
        [_progress setUserInfoObject: error forKey: kCBLProgressError];
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
            _progress.completedUnitCount = _bytesRead;
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
