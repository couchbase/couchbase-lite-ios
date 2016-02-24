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
#import "CBL_BlobStoreWriter.h"
#import "CBLInternal.h"
#import "CBLBase64.h"
#import "CBLMisc.h"
#import "CouchbaseLitePrivate.h"
#import "CollectionUtils.h"
#import "MYStreamUtils.h"
#import "CBLGZip.h"


UsingLogDomain(Sync);


@interface CBLMultipartDocumentReader () <CBLMultipartReaderDelegate, NSStreamDelegate>
@end


@implementation CBLMultipartDocumentReader
{
    @private
    CBLDatabase* _database;
    BOOL _attachments;
    CBLStatus _status;
    CBLMultipartReader* _multipartReader;
    NSMutableData* _jsonBuffer;
    BOOL _jsonCompressed;
    CBL_BlobStoreWriter* _curAttachment;
    NSMutableDictionary* _attachmentsByName;      // maps attachment name --> CBL_BlobStoreWriter
    NSMutableDictionary* _attachmentsByDigest;    // maps attachment MD5 --> CBL_BlobStoreWriter
    NSMutableDictionary* _document;
    CBLMultipartDocumentReaderCompletionBlock _completionBlock;
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
        LogVerbose(Sync, @"%@: has attachments, %@", self, contentType);
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
    LogVerbose(Sync, @"%@: Finished loading (%u attachments)",
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
        LogVerbose(Sync, @"%@: Reading from input stream...", self);
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
    __typeof(_completionBlock) completionBlock = _completionBlock;
    completionBlock(self);
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
        LogVerbose(Sync, @"%@: Starting attachment #%u...",
              self, (unsigned)_attachmentsByDigest.count + 1);
        _curAttachment = [_database attachmentWriter];
        if (!_curAttachment) {
            Warn(@"Cannot create a blob store writer for the attachment.");
            _status = kCBLStatusAttachmentError;
            return NO;
        }

        // See whether the attachment name is in the headers.
        NSString* name = nil;
        NSString* disposition = headers[@"Content-Disposition"];
        if ([disposition hasPrefix: @"attachment; filename="]) {
            // TODO: Parse this less simplistically. Right now it assumes it's in exactly the same
            // format generated by -[CBL_Pusher uploadMultipartRevision:] and CouchDB 1.6.
            name = CBLUnquoteString([disposition substringFromIndex: 21]);
            if (name) {
                _curAttachment.name = name;
                _attachmentsByName[name] = _curAttachment;
            }
        }

        NSString* contentEncoding = headers[@"Content-Encoding"];
        if ([contentEncoding isEqualToString: @"gzip"]) {
            if (name && ![_document[@"_attachments"][name][@"encoding"] isEqual: @"gzip"]) {
                Warn(@"Attachment '%@' MIME body is gzipped but attachment isn't", name);
                _status = kCBLStatusUnsupportedType;
                return NO;
            }
        } else if (contentEncoding) {
            Warn(@"Received unsupported Content-Encoding '%@'", contentEncoding);
            _status = kCBLStatusUnsupportedType;
            return NO;
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
        if (WillLogVerbose(Sync)) {
            CBLBlobKey key = _curAttachment.blobKey;
            NSData* keyData = [NSData dataWithBytes: &key length: sizeof(key)];
            LogVerbose(Sync, @"%@: Finished attachment #%u: len=%uk, digest=%@, SHA1=%@",
                  self, (unsigned)_attachmentsByDigest.count+1, (unsigned)_curAttachment.bytesWritten/1024,
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
        json = [CBLGZip dataByDecompressingData: json];
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
                if (digest && ![writer verifyDigest: digest]) {
                    return NO;
                }
                attachment[@"digest"] = writer.MD5DigestString;
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
            if (writer.bytesWritten != length) {
                Warn(@"%@: Attachment '%@' has incorrect length field %@ (should be %llu)",
                    self, attachmentName, lengthObj, writer.bytesWritten);
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
