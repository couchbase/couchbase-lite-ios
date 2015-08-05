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

#import "MYBlockUtils.h"
#import "MYURLUtils.h"
#import "MYZip.h"


#define kProgressInterval 0.25


@implementation CBLAttachmentDownloader
{
    NSDictionary* _metadata;
    CBLAttachmentDownloaderProgressBlock _onProgress;
    CBL_BlobStoreWriter* _writer;
    MYZip* _zipper;
    uint64_t _bytesRead, _contentLength;
    NSError* _error;
    void (^_noteProgress)();
}


- (instancetype) initWithDbURL: (NSURL*)dbURL
                      database: (CBLDatabase*)database
                      document: (NSDictionary*)doc
                attachmentName: (NSString*)name
                    onProgress: (CBLAttachmentDownloaderProgressBlock)onProgress
                  onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    NSURL* url = [[dbURL URLByAppendingPathComponent: doc.cbl_id] URLByAppendingPathComponent: name];
    NSMutableString* urlStr = [url.absoluteString mutableCopy];
    [urlStr appendFormat: @"?rev=%@", doc.cbl_rev];
    self = [super initWithMethod: @"GET" URL: $url(urlStr) body: nil
                  requestHeaders: nil
                    onCompletion: onCompletion];
    if (self) {
        _metadata = [doc.cbl_attachments[name] copy];
        _onProgress = onProgress;
        _writer = [database attachmentWriter];
        _writer.name = name;
        _noteProgress = MYThrottledBlock(kProgressInterval, ^{
            onProgress(MIN(_bytesRead, _contentLength-1), _contentLength, nil);
        });
    }
    return self;
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    CBLStatus status = (CBLStatus) ((NSHTTPURLResponse*)response).statusCode;
    if (status < 300) {
        _bytesRead = 0;
        _contentLength = [((NSHTTPURLResponse*)response).allHeaderFields[@"Content-Length"] longLongValue];
        if (_contentLength == 0) {
            NSNumber* len = _metadata[@"encoded_length"] ?: _metadata[@"length"];
            _contentLength = len ? len.longLongValue : UINT64_MAX;
        }

        // NSURLConnection unfortunately detects the Content-Encoding header and decodes the
        // gzipped data before sending it to me, so if the attachment is supposed to be encoded,
        // I will need to re-encode it.
        if ([_metadata[@"encoding"] isEqualToString: @"gzip"])
            _zipper = [[MYZip alloc] initForCompressing: YES];
        _noteProgress();
    }
    [super connection: connection didReceiveResponse: response];
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [super connection: connection didReceiveData: data];
    [self appendData: data];
    _bytesRead += data.length;
    _noteProgress();
}


- (void) appendData: (NSData*)data {
    CBL_BlobStoreWriter* writer = _writer;
    if (_zipper) {
        [_zipper addBytes: data.bytes length: data.length
                 onOutput: ^(const void *bytes, size_t length) {
                     [writer appendData: [[NSData alloc] initWithBytesNoCopy: (void*)bytes
                                                                      length: length
                                                                freeWhenDone: NO]];
        }];
    } else if (data) {
        [writer appendData: data];
    }
}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self appendData: nil]; // flush zip encoder buffer
    CBL_BlobStoreWriter* writer = _writer;
    [writer finish];
    if ([writer verifyDigest: _metadata[@"digest"]]) {
        [_writer install];
        _writer = nil;
        [self clearConnection];
        _onProgress(_bytesRead, _bytesRead, nil); // immediately report 100% complete
        [self respondWithResult: writer error: nil];
    } else {
        [self cancelWithStatus: kCBLStatusBadAttachment];
    }
}


- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [super connection: connection didFailWithError: error];
    _onProgress(_bytesRead, _contentLength, error); // report error
}


- (void) clearConnection {
    [super clearConnection];
    [_writer cancel];
    _writer = nil;
}


@end
