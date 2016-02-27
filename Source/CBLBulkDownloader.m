//
//  CBLBulkDownloader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/20/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLBulkDownloader.h"
#import "CBLMultipartReader.h"
#import "CBLMultipartDocumentReader.h"
#import "CBLRestPuller.h"
#import "CBL_Revision.h"
#import "CBLDatabase+Internal.h"
#import "CBLMisc.h"

#import "CollectionUtils.h"


@interface CBLBulkDownloader () <CBLMultipartReaderDelegate>
@end


@implementation CBLBulkDownloader
{
    CBLDatabase* _db;
    BOOL _attachments;
    CBLMultipartReader* _topReader;
    CBLMultipartDocumentReader* _docReader;
    unsigned _docCount;
    CBLBulkDownloaderDocumentBlock _onDocument;
}


- (instancetype) initWithDbURL: (NSURL*)dbURL
                      database: (CBLDatabase*)database
                     revisions: (NSArray*)revs
                   attachments: (BOOL)attachments
                    onDocument: (CBLBulkDownloaderDocumentBlock)onDocument
                  onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    // Build up a JSON body describing what revisions we want:
    NSArray* keys = [revs my_map: ^(CBL_Revision* rev) {
        NSArray* attsSince = nil;
        if (attachments) {
            attsSince = [database.storage getPossibleAncestorRevisionIDs: rev
                                                               limit: kMaxNumberOfAttsSince
                                                     onlyAttachments: YES];
            if (attsSince.count == 0)
                attsSince = nil;
        }
        return $dict({@"id", rev.docID},
                     {@"rev", rev.revID},
                     {@"atts_since", attsSince});
    }];

    NSString* query = attachments ?@"_bulk_get?revs=true&attachments=true" :@"_bulk_get?revs=true";

    self = [super initWithMethod: @"POST"
                             URL: CBLAppendToURL(dbURL, query)
                            body: @{@"docs": keys}
                    onCompletion: onCompletion];
    if (self) {
        _db = database;
        _attachments = attachments;
        _onDocument = onDocument;

        [_request setValue: @"multipart/related" forHTTPHeaderField: @"Accept"];
        [_request setValue: @"gzip" forHTTPHeaderField: @"X-Accept-Part-Encoding"];
}
    return self;
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _request.URL.path);
}


#pragma mark - URL CONNECTION CALLBACKS:


- (BOOL) retry {
    if (_docCount > 0) {
        // Don't retry if we've already read any docs, because we'd get
        // those docs again and confuse the replicator.
        return NO;
    }
    return [super retry];
}


- (void) didReceiveResponse:(NSHTTPURLResponse *)response {
    [super didReceiveResponse: response];
    if (_status < 300) {
        // Check the content type to see whether it's a multipart response:
        NSString* contentType = _responseHeaders[@"Content-Type"];
        _topReader = [[CBLMultipartReader alloc] initWithContentType: contentType
                                                            delegate: self];
        if (!_topReader) {
            Warn(@"%@ got invalid Content-Type '%@'", self, contentType);
            [self cancelWithStatus: kCBLStatusUpstreamError message: @"Invalid Content-Type"];
            return;
        }
    }
}


- (void) didReceiveData:(NSData *)data {
    [super didReceiveData: data];
    [_topReader appendData: data];
    if (_topReader.error) {
        [self cancelWithStatus: kCBLStatusUpstreamError message: _topReader.error];
    }
}


- (void)connectionDidFinishLoading {
    LogVerbose(Sync, @"%@: Finished loading (%u documents)", self, _docCount);
    if (!_topReader.finished) {
        Warn(@"%@ got unexpected EOF", self);
        [self cancelWithStatus: kCBLStatusUpstreamError
                       message: @"Error reading multipart response"];
        return;
    }
    
    [self clearConnection];
    [self respondWithResult: self error: nil];
}


#pragma mark - MULTIPART CALLBACKS:


/** This method is called when a part's headers have been parsed, before its data is parsed. */
- (BOOL) startedPart: (NSDictionary*)headers {
    Assert(!_docReader);
    LogVerbose(Sync, @"%@: Starting new document; ID=\"%@\"", self, headers[@"X-Doc-ID"]);
    _docReader = [[CBLMultipartDocumentReader alloc] initWithDatabase: _db];
    _docReader.headers = headers;
    return YES;
}

/** This method is called to append data to a part's body. */
- (BOOL) appendToPart: (NSData*)data {
    Assert(_docReader);
    if (![_docReader appendData: data]) {
        [self cancelWithStatus: _docReader.status message: nil];
        return NO;
    }
    return YES;
}

/** This method is called when a part is complete. */
- (BOOL) finishedPart {
    LogVerbose(Sync, @"%@: Finished document", self);
    Assert(_docReader);
    if (![_docReader finish]) {
        [self cancelWithStatus: _docReader.status message: nil];
        _docReader = nil;
        return NO;
    }
    ++_docCount;
    __typeof(_onDocument) onDocument = _onDocument;
    onDocument(_docReader.document);
    _docReader = nil;
    return YES;
}



@end
