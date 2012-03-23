//
//  TDMultipartDownloader.m
//  TouchDB
//
//  Created by Jens Alfke on 1/31/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDMultipartDownloader.h"
#import "TDDatabase+Attachments.h"
#import "TDBlobStore.h"
#import "TDInternal.h"
#import "TDBase64.h"
#import "TDMisc.h"
#import "CollectionUtils.h"


@implementation TDMultipartDownloader


@synthesize revision=_revision, document=_document;


- (id) initWithURL: (NSURL*)url
          database: (TDDatabase*)database
          revision: (TDRevision*)revision
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    self = [super initWithMethod: @"GET" URL: url body: nil onCompletion: onCompletion];
    if (self) {
        _database = database;
        _revision = [revision retain];
    }
    return self;
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _request.URL.path);
}


- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    [request setValue: @"multipart/related" forHTTPHeaderField: @"Accept"];
    request.HTTPBody = body;
}


- (void) dealloc {
    [_document release];
    [_revision release];
    [_attachmentsByDigest autorelease];
    [super dealloc];
}


- (void) clearConnection {
    [_curAttachment cancel];
    setObj(&_curAttachment, nil);
    setObj(&_multipartReader, nil);
    setObj(&_jsonBuffer, nil);
    [super clearConnection];
}


- (BOOL) parseJSONBuffer {
    id document = [NSJSONSerialization JSONObjectWithData: _jsonBuffer options: 0 error: nil];
    setObj(&_jsonBuffer, nil);
    if (![document isKindOfClass: [NSDictionary class]]) {
        Warn(@"%@: received unparseable JSON data '%@'",
             self, [_jsonBuffer my_UTF8ToString]);
        [self cancelWithStatus: 502];
        return NO;
    }
    _document = [document copy];
    return YES;
}


- (TDBlobStoreWriter*)blobWriterForAttachment: (NSDictionary*)attachment {
    NSString* digest = [attachment objectForKey: @"digest"];
    return digest ? [_attachmentsByDigest objectForKey: digest] : nil;
}


- (BOOL) registerAttachments {
    NSDictionary* attachments = [_document objectForKey: @"_attachments"];
    if (![attachments isKindOfClass: [NSDictionary class]]) 
        return NO;
    NSUInteger nAttachmentsInDoc = 0;
    for (NSDictionary* attachment in attachments.allValues) {
        if ([[attachment objectForKey: @"follows"] isEqual: $true]) {
            // Check that each attachment in the JSON corresponds to an attachment MIME body:
            TDBlobStoreWriter* writer = [self blobWriterForAttachment: attachment];
            if (!writer)
                return NO;
            // Check that the length matches:
            NSNumber* lengthObj = [attachment objectForKey: @"encoded_length"]
                               ?: [attachment objectForKey: @"length"];
            if (!lengthObj)
                return NO;
            if (writer.length != [$castIf(NSNumber, lengthObj) unsignedLongLongValue])
                return NO;
            ++nAttachmentsInDoc;
        }
    }
    if (nAttachmentsInDoc < _attachmentsByDigest.count)
        return NO;  // Some MIME bodies didn't match attachments in the document
    // If everything's copacetic, hand over the (uninstalled) blobs to the database to remember:
    [_database rememberAttachmentWritersForDigests: _attachmentsByDigest];
    return YES;
}


#pragma mark - URL CONNECTION CALLBACKS:


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    Assert(_database, @"Didn't set database property");
    [super connection: connection didReceiveResponse: response];
    if (!_connection)
        return;
    
    // Check the content type to see whether it's a multipart response:
    NSDictionary* headers = [(NSHTTPURLResponse*)response allHeaderFields];
    NSString* contentType = [headers objectForKey: @"Content-Type"];
    if ([contentType hasPrefix: @"multipart/"]) {
        // Multipart, so initialize the parser:
        LogTo(SyncVerbose, @"%@: has attachments, %@", self, contentType);
        _multipartReader = [[TDMultipartReader alloc] initWithContentType: contentType delegate: self];
        if (!_multipartReader) {
            Warn(@"%@: received invalid content type '%@'", self, contentType);
            [self cancelWithStatus: 406];
            return;
        }
        _attachmentsByDigest = [[NSMutableDictionary alloc] init];
    } else {
        // No multipart, so no attachments. Body is pure JSON:
        _jsonBuffer = [[NSMutableData alloc] initWithCapacity: 1024];
    }
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [super connection: connection didReceiveData: data];
    if (_multipartReader) {
        [_multipartReader appendData: data];
        if (_multipartReader.failed) {
            Warn(@"%@: received unparseable MIME multipart response", self);
            [self cancelWithStatus: 502];
        }
    } else {
        [_jsonBuffer appendData: data];
    }
}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    LogTo(SyncVerbose, @"%@: Finished loading (%u attachments)", self, _attachmentsByDigest.count);
    if (_multipartReader) {
        if (!_multipartReader.finished) {
            Warn(@"%@: received incomplete MIME multipart response", self);
            [self cancelWithStatus: 502];
            return;
        }
        
        if (![self registerAttachments]) {
            [self cancelWithStatus: 400];
            return;
        }
    } else {
        if (![self parseJSONBuffer])
            return;
    }
    
    [self clearConnection];
    [self respondWithResult: self error: nil];
}


#pragma mark - MIME PARSER CALLBACKS:


/** Callback: A part's headers have been parsed, but not yet its data. */
- (void) startedPart: (NSDictionary*)headers {
    // First MIME part is the document's JSON body; the rest are attachments.
    if (!_document)
        _jsonBuffer = [[NSMutableData alloc] initWithCapacity: 1024];
    else {
        LogTo(SyncVerbose, @"%@: Starting attachment #%u...", self, _attachmentsByDigest.count + 1);
        _curAttachment = [[_database attachmentWriter] retain];
    }
}


/** Callback: Append data to a MIME part's body. */
- (void) appendToPart: (NSData*)data {
    if (_jsonBuffer)
        [_jsonBuffer appendData: data];
    else
        [_curAttachment appendData: data];
}


/** Callback: A MIME part is complete. */
- (void) finishedPart {
    if (_jsonBuffer) {
        [self parseJSONBuffer];
    } else {
        // Finished downloading an attachment. Remember the association from the MD5 digest
        // (which appears in the body's _attachments dict) to the blob-store key of the data.
        [_curAttachment finish];
        TDMD5Key md5 = _curAttachment.MD5Digest;
        NSString* md5Str = [@"md5-" stringByAppendingString: [TDBase64 encode: &md5
                                                                       length: sizeof(md5)]];
#ifndef MY_DISABLE_LOGGING
        if (WillLogTo(SyncVerbose)) {
            TDBlobKey key = _curAttachment.blobKey;
            NSData* keyData = [NSData dataWithBytes: &key length: sizeof(key)];
            LogTo(SyncVerbose, @"%@: Finished attachment #%u: len=%uk, digest=%@, SHA1=%@",
                  self, _attachmentsByDigest.count+1, (unsigned)_curAttachment.length/1024,
                  md5Str, keyData);
        }
#endif
        [_attachmentsByDigest setObject: _curAttachment forKey: md5Str];
        setObj(&_curAttachment, nil);
    }
}


@end




TestCase(TDMultipartDownloader) {
    //These URLs only work for me!
    if (!$equal(NSUserName(), @"snej"))
        return;
    
    RequireTestCase(TDBlobStore);
    RequireTestCase(TDMultipartReader_Simple);
    RequireTestCase(TDMultipartReader_Types);
    
    TDDatabase* db = [TDDatabase createEmptyDBAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: @"TDMultipartDownloader"]];
    //NSString* urlStr = @"http://127.0.0.1:5984/demo-shopping-attachments/2F9078DF-3C72-44C2-8332-B07B3A29FFE4"
    NSString* urlStr = @"http://127.0.0.1:5984/attach-test/oneBigAttachment";
    urlStr = [urlStr stringByAppendingString: @"?revs=true&attachments=true"];
    NSURL* url = [NSURL URLWithString: urlStr];
    __block BOOL done = NO;
    [[[TDMultipartDownloader alloc] initWithURL: url
                                       database: db
                                       revision: nil
                                   onCompletion: ^(id result, NSError * error)
     {
         CAssertNil(error);
         TDMultipartDownloader* request = result;
         Log(@"Got document: %@", request.document);
         NSDictionary* attachments = [request.document objectForKey: @"_attachments"];
         CAssert(attachments.count >= 1);
         CAssertEq(db.attachmentStore.count, 0u);
         for (NSDictionary* attachment in attachments.allValues) {
             TDBlobStoreWriter* writer = [request blobWriterForAttachment: attachment];
             CAssert(writer);
             CAssert([writer install]);
             NSData* blob = [db.attachmentStore blobForKey: writer.blobKey];
             Log(@"Found %u bytes of data for attachment %@", blob.length, attachment);
             NSNumber* lengthObj = [attachment objectForKey: @"encoded_length"] ?: [attachment objectForKey: @"length"];
             CAssertEq(blob.length, [lengthObj unsignedLongLongValue]);
             CAssertEq(writer.length, blob.length);
         }
         CAssertEq(db.attachmentStore.count, attachments.count);
         done = YES;
    }] autorelease];
    
    while (!done)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
}
