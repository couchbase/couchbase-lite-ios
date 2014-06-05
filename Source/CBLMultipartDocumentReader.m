//
//  CBLMultipartDocumentReader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/29/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLMultipartDocumentReader.h"
#import "CBLDatabase+Attachments.h"
#import "CBL_BlobStore.h"
#import "CBLInternal.h"
#import "CBLBase64.h"
#import "CBLMisc.h"
#import "CollectionUtils.h"
#import "MYStreamUtils.h"
#import "GTMNSData+zlib.h"


@interface CBLMultipartDocumentReader () <CBLMultipartReaderDelegate, NSStreamDelegate>
@end


@implementation CBLMultipartDocumentReader
{
    __strong id _retainSelf; // Used to keep this object alive by keeping a reference to self
}


+ (NSDictionary*) readData: (NSData*)data
                   headers: (NSDictionary*)headers
                toDatabase: (CBLDatabase*)database
                    status: (CBLStatus*)outStatus
{
    if (data.length == 0) {
        *outStatus = kCBLStatusBadJSON;
        return nil;
    }
    NSDictionary* result = nil;
    CBLMultipartDocumentReader* reader = [[self alloc] initWithDatabase: database];
    if ([reader setHeaders: headers]
            && [reader appendData: data]
            && [reader finish]) {
        result = reader.document;
    }
    if (outStatus)
        *outStatus = reader.status;
    return result;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
{
    Assert(database);
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}


- (void) dealloc {
    [_curAttachment cancel];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[_id=\"%@\"]", self.class, _document.cbl_id];
}



@synthesize status=_status, document=_document;


- (NSUInteger) attachmentCount {
    return _attachmentsByDigest.count;
}


- (BOOL) setHeaders: (NSDictionary*)headers {
    NSString* contentType = headers[@"Content-Type"];
    if ([contentType hasPrefix: @"multipart/"]) {
        // Multipart, so initialize the parser:
        LogTo(SyncVerbose, @"%@: has attachments, %@", self, contentType);
        _multipartReader = [[CBLMultipartReader alloc] initWithContentType: contentType delegate: self];
        if (_multipartReader) {
            _attachmentsByName = [[NSMutableDictionary alloc] init];
            _attachmentsByDigest = [[NSMutableDictionary alloc] init];
            return YES;
        }
    } else if (contentType == nil || [contentType hasPrefix: @"application/json"]
                                  || [contentType hasPrefix: @"text/plain"]) {
        // No multipart, so no attachments. Body is pure JSON. (We allow text/plain because CouchDB
        // sends JSON responses using the wrong content-type.)
        [self startJSONBufferWithHeaders: headers];
        return YES;
    }
    // Unknown/invalid MIME type:
    _status = kCBLStatusNotAcceptable;
    return NO;
}


- (void) startJSONBufferWithHeaders: (NSDictionary*)headers {
    _jsonBuffer = [[NSMutableData alloc] initWithCapacity: 1024];
    NSString* contentEncoding = headers[@"Content-Encoding"];
    _jsonCompressed = contentEncoding && [contentEncoding rangeOfString: @"gzip"].length > 0;
}


- (BOOL) appendData:(NSData *)data {
    if (_multipartReader) {
        [_multipartReader appendData: data];
        if (_multipartReader.error) {
            Warn(@"%@: received unparseable MIME multipart response: %@",
                 self, _multipartReader.error);
            _status = kCBLStatusUpstreamError;
            return NO;
        }
    } else {
        [_jsonBuffer appendData: data];
    }
    return YES;
}


- (BOOL) finish {
    LogTo(SyncVerbose, @"%@: Finished loading (%u attachments)",
          self, (unsigned)_attachmentsByDigest.count);
    if (_multipartReader) {
        if (!_multipartReader.finished) {
            Warn(@"%@: received incomplete MIME multipart response", self);
            _status = kCBLStatusUpstreamError;
            return NO;
        }
        
        if (![self registerAttachments]) {
            _status = kCBLStatusUpstreamError;
            return NO;
        }
    } else {
        if (![self parseJSONBuffer])
            return NO;
    }
    _status = kCBLStatusCreated;
    return YES;
}


#pragma mark - ASYNCHRONOUS MODE:


+ (CBLStatus) readStream: (NSInputStream*)stream
                 headers: (NSDictionary*)headers
              toDatabase: (CBLDatabase*)database
                    then: (CBLMultipartDocumentReaderCompletionBlock)onCompletion
{
    CBLMultipartDocumentReader* reader = [[self alloc] initWithDatabase: database];
    return [reader readStream: stream headers: headers then: onCompletion];
}


- (CBLStatus) readStream: (NSInputStream*)stream
                 headers: (NSDictionary*)headers
                    then: (CBLMultipartDocumentReaderCompletionBlock)completionBlock
{
    if ([self setHeaders: headers]) {
        LogTo(SyncVerbose, @"%@: Reading from input stream...", self);
        _retainSelf = self;  // balanced by release in -finishAsync:
        _completionBlock = [completionBlock copy];
        [stream open];
        stream.delegate = self;
        [stream scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    }
    return _status;
}


- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)eventCode {
    BOOL finish = NO;
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable:
            finish = ![self readFromStream: (NSInputStream*)stream];
            break;
        case NSStreamEventEndEncountered:
            finish = YES;
            break;
        case NSStreamEventErrorOccurred:
            Warn(@"%@: error reading from stream: %@", self, stream.streamError);
            _status = kCBLStatusUpstreamError;
            finish = YES;
            break;
        default:
            break;
    }
    if (finish)
        [self finishAsync: (NSInputStream*)stream];
}


- (BOOL) readFromStream: (NSInputStream*)stream {
    BOOL readOK = [stream my_readData: ^(NSData *data) {
        [self appendData: data];
    }];
    if (!readOK) {
        Warn(@"%@: error reading from stream: %@", self, stream.streamError);
        _status = kCBLStatusUpstreamError;
    }
    return !CBLStatusIsError(_status);
}


- (void) finishAsync: (NSInputStream*)stream {
    stream.delegate = nil;
    [stream close];
    if (!CBLStatusIsError(_status))
        [self finish];
    _completionBlock(self);
    _completionBlock = nil;
    _retainSelf = nil;  // clears the reference acquired in -readStream:
}


#pragma mark - MIME PARSER CALLBACKS:


/** Callback: A part's headers have been parsed, but not yet its data. */
- (BOOL) startedPart: (NSDictionary*)headers {
    // First MIME part is the document's JSON body; the rest are attachments.
    if (!_document) {
        [self startJSONBufferWithHeaders: headers];
    } else {
        LogTo(SyncVerbose, @"%@: Starting attachment #%u...",
              self, (unsigned)_attachmentsByDigest.count + 1);
        _curAttachment = [_database attachmentWriter];
        
        // See whether the attachment name is in the headers.
        NSString* disposition = headers[@"Content-Disposition"];
        if ([disposition hasPrefix: @"attachment; filename="]) {
            // TODO: Parse this less simplistically. Right now it assumes it's in exactly the same
            // format generated by -[CBL_Pusher uploadMultipartRevision:]. CouchDB (as of 1.2) doesn't
            // output any headers at all on attachments so there's no compatibility issue yet.
            NSString* name = CBLUnquoteString([disposition substringFromIndex: 21]);
            if (name)
                _attachmentsByName[name] = _curAttachment;
        }
    }
    return YES;
}


/** Callback: Append data to a MIME part's body. */
- (BOOL) appendToPart: (NSData*)data {
    if (_jsonBuffer)
        [_jsonBuffer appendData: data];
    else
        [_curAttachment appendData: data];
    return YES;
}


/** Callback: A MIME part is complete. */
- (BOOL) finishedPart {
    if (_jsonBuffer) {
        [self parseJSONBuffer];
    } else {
        // Finished downloading an attachment. Remember the association from the MD5 digest
        // (which appears in the body's _attachments dict) to the blob-store key of the data.
        [_curAttachment finish];
        NSString* md5Str = _curAttachment.MD5DigestString;
#ifndef MY_DISABLE_LOGGING
        if (WillLogTo(SyncVerbose)) {
            CBLBlobKey key = _curAttachment.blobKey;
            NSData* keyData = [NSData dataWithBytes: &key length: sizeof(key)];
            LogTo(SyncVerbose, @"%@: Finished attachment #%u: len=%uk, digest=%@, SHA1=%@",
                  self, (unsigned)_attachmentsByDigest.count+1, (unsigned)_curAttachment.length/1024,
                  md5Str, keyData);
        }
#endif
        _attachmentsByDigest[md5Str] = _curAttachment;
        _curAttachment = nil;
    }
    return YES;
}


#pragma mark - INTERNALS:


- (BOOL) parseJSONBuffer {
    NSData* json = _jsonBuffer;
    _jsonBuffer = nil;
    if (_jsonCompressed) {
        json = [NSData gtm_dataByInflatingData: json];
        if (!json) {
            Warn(@"%@: received corrupt gzip-encoded JSON part", self);
            _status = kCBLStatusUpstreamError;
            return NO;
        }
    }
    id document = [CBLJSON JSONObjectWithData: json
                                       options: CBLJSONReadingMutableContainers
                                         error: NULL];
    if (![document isKindOfClass: [NSDictionary class]]) {
        Warn(@"%@: received unparseable JSON data '%@'",
             self, ([json my_UTF8ToString] ?: json));
        _status = kCBLStatusUpstreamError;
        return NO;
    }
    _document = document;
    return YES;
}


- (BOOL) registerAttachments {
    NSDictionary* attachments = _document.cbl_attachments;
    if (attachments && ![attachments isKindOfClass: [NSDictionary class]]) {
        Warn(@"%@: _attachments property is not a dictionary", self);
        return NO;
    }
    NSUInteger nAttachmentsInDoc = 0;
    for (NSString* attachmentName in attachments) {
        NSMutableDictionary* attachment = attachments[attachmentName];

        // Get the length:
        NSNumber* lengthObj = attachment[@"encoded_length"] ?: attachment[@"length"];
        if (![lengthObj isKindOfClass: [NSNumber class]]) {
            Warn(@"%@: Attachment '%@' has invalid length property %@",
                 self, attachmentName, lengthObj);
            return NO;
        }
        UInt64 length = lengthObj.unsignedLongLongValue;

        if ([attachment[@"follows"] isEqual: $true]) {
            // Check that each attachment in the JSON corresponds to an attachment MIME body.
            // Look up the attachment by either its MIME Content-Disposition header or MD5 digest:
            NSString* digest = attachment[@"digest"];
            CBL_BlobStoreWriter* writer = _attachmentsByName[attachmentName];
            if (writer) {
                // Identified the MIME body by the filename in its Disposition header:
                NSString* actualMD5Digest = writer.MD5DigestString;
                NSString* actualSHADigest = writer.SHA1DigestString;
                if (digest && !$equal(digest, actualMD5Digest) && !$equal(digest, actualSHADigest)) {
                    Warn(@"%@: Attachment '%@' has incorrect digest property (%@; should be %@ or %@)",
                         self, attachmentName, digest, actualMD5Digest, actualSHADigest);
                    return NO;
                }
                attachment[@"digest"] = actualMD5Digest;
            } else if (digest) {
                // Else look up the MIME body by its computed digest:
                writer = _attachmentsByDigest[digest];
                if (!writer) {
                    Warn(@"%@: Attachment '%@' does not appear in a MIME body",
                         self, attachmentName);
                    return NO;
                }
            } else if (attachments.count == 1 && _attachmentsByDigest.count == 1) {
                // Else there's only one attachment, so just assume it matches & use it:
                writer = [_attachmentsByDigest allValues][0];
                attachment[@"digest"] = writer.MD5DigestString;
            } else {
                // No digest metatata, no filename in MIME body; give up:
                Warn(@"%@: Attachment '%@' has no digest metadata; cannot identify MIME body",
                     self, attachmentName);
                return NO;
            }
            
            // Check that the length matches:
            if (writer.length != length) {
                Warn(@"%@: Attachment '%@' has incorrect length field %@ (should be %llu)",
                    self, attachmentName, lengthObj, writer.length);
                return NO;
            }
            
            ++nAttachmentsInDoc;
        } else if (attachment[@"data"] != nil && length > 1000) {
            // This isn't harmful but it's quite inefficient of the server
            Warn(@"%@: Attachment '%@' sent inline (length=%llu)", self, attachmentName, length);
        }
    }
    if (nAttachmentsInDoc < _attachmentsByDigest.count) {
        Warn(@"%@: More MIME bodies (%u) than attachments (%u)",
            self, (unsigned)_attachmentsByDigest.count, (unsigned)nAttachmentsInDoc);
        return NO;
    }
    
    // If everything's copacetic, hand over the (uninstalled) blobs to the database to remember:
    [_database rememberAttachmentWritersForDigests: _attachmentsByDigest];
    return YES;
}


@end




#if DEBUG
#import "CBL_BlobStore.h"

TestCase(CBLMultipartDocumentReader) {
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"cbl_test.sqlite3"];
    CBLDatabase *db = [CBLDatabase createEmptyDBAtPath: path];
    CAssert([db open: nil]);

    NSData* mime = CBLContentsOfTestFile(@"Multipart1.mime");
    NSDictionary* headers = @{@"Content-Type": @"multipart/mixed; boundary=\"BOUNDARY\""};
    CBLStatus status;
    NSDictionary* dict = [CBLMultipartDocumentReader readData: mime headers: headers toDatabase: db status: &status];
    CAssert(!CBLStatusIsError(status));
    CAssertEqual(dict, (@{@"_id": @"THX-1138",
                         @"_rev": @"1-foobar",
                         @"_attachments": @{
                                 @"mary.txt": @{@"type": @"text/doggerel", @"length": @52,
                                                @"follows": @YES,
                                                @"digest": @"md5-1WWSGl9mJACzGjclAafpfQ=="}
                                 }}));
    NSDictionary* attachment = (dict[@"_attachments"])[@"mary.txt"];
    CBL_BlobStoreWriter* writer = [db attachmentWriterForAttachment: attachment];
    Assert(writer);
    AssertEq(writer.length, 52u);

    mime = CBLContentsOfTestFile(@"MultipartBinary.mime");
    headers = @{@"Content-Type": @"multipart/mixed; boundary=\"dc0bf3cdc9a6c6e4c46fe2a361c8c5d7\""};
    dict = [CBLMultipartDocumentReader readData: mime headers: headers toDatabase: db status: &status];
    CAssert(!CBLStatusIsError(status));
    CAssertEqual(dict, (@{@"_id": @"038c536dc29ff0f4127705879700062c",
                          @"_rev":@"3-e715bcf1865f8283ab1f0ba76e7a92ba",
                          @"_attachments":@{
                                  @"want3.jpg":@{
                                          @"content_type":@"image/jpeg",
                                          @"revpos":@3,
                                          @"digest":@"md5-/rAceS7EjR+CDHdYp8zKOg==",
                                          @"length":@24758,
                                          @"follows":@YES},
                                  @"Toad.gif":@{
                                          @"content_type":@"image/gif",
                                          @"revpos":@2,
                                          @"digest":@"md5-6UpXIDR/olzgZrDhsMe7Sw==",
                                          @"length":@6566,
                                          @"follows":@YES}}}));
    attachment = (dict[@"_attachments"])[@"Toad.gif"];
    writer = [db attachmentWriterForAttachment: attachment];
    Assert(writer);
    AssertEq(writer.length, 6566u);
    attachment = (dict[@"_attachments"])[@"want3.jpg"];
    writer = [db attachmentWriterForAttachment: attachment];
    Assert(writer);
    AssertEq(writer.length, 24758u);

    // Read data that's equivalent to the last one except the JSON is gzipped:
    mime = CBLContentsOfTestFile(@"MultipartBinary.mime");
    headers = @{@"Content-Type": @"multipart/mixed; boundary=\"dc0bf3cdc9a6c6e4c46fe2a361c8c5d7\""};
    NSDictionary* unzippedDict = [CBLMultipartDocumentReader readData: mime headers: headers toDatabase: db status: &status];
    CAssertEqual(unzippedDict, dict);
}

#endif
