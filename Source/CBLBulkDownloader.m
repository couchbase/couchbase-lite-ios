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
#import "CBL_Puller.h"
#import "CBL_Revision.h"
#import "CBLDatabase+Internal.h"
#import "CBLMisc.h"

#import "CollectionUtils.h"


@interface CBLBulkDownloader () <CBLMultipartReaderDelegate>
@end


@implementation CBLBulkDownloader
{
    CBLDatabase* _db;
    CBLMultipartReader* _topReader;
    CBLMultipartDocumentReader* _docReader;
    unsigned _docCount;
    CBLBulkDownloaderDocumentBlock _onDocument;
}


- (instancetype) initWithDbURL: (NSURL*)dbURL
                      database: (CBLDatabase*)database
                requestHeaders: (NSDictionary *) requestHeaders
                     revisions: (NSArray*)revs
                    onDocument: (CBLBulkDownloaderDocumentBlock)onDocument
                  onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    // Build up a JSON body describing what revisions we want:
    NSArray* keys = [revs my_map: ^(CBL_Revision* rev) {
        BOOL hasAttachment;
        NSArray* attsSince = [_db getPossibleAncestorRevisionIDs: rev
                                                           limit: kMaxNumberOfAttsSince
                                                   hasAttachment: &hasAttachment];
        if (!hasAttachment || attsSince.count == 0)
            attsSince = nil;
        return $dict({@"id", rev.docID},
                     {@"rev", rev.revID},
                     {@"atts_since", attsSince});
    }];
    NSDictionary* body = @{@"docs": keys};

    self = [super initWithMethod: @"POST"
                             URL: CBLAppendToURL(dbURL, @"_bulk_get?revs=true&attachments=true")
                            body: body
                  requestHeaders: requestHeaders
                    onCompletion: onCompletion];
    if (self) {
        _db = database;
        _onDocument = onDocument;
    }
    return self;
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _request.URL.path);
}


- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    request.HTTPBody = [CBLJSON dataWithJSONObject: body options: 0 error: NULL];
    [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    [request setValue: @"multipart/related" forHTTPHeaderField: @"Accept"];
    [request setValue: @"gzip" forHTTPHeaderField: @"X-Accept-Part-Encoding"];
}


#pragma mark - URL CONNECTION CALLBACKS:


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    CBLStatus status = (CBLStatus) ((NSHTTPURLResponse*)response).statusCode;
    if (status < 300) {
        // Check the content type to see whether it's a multipart response:
        NSDictionary* headers = [(NSHTTPURLResponse*)response allHeaderFields];
        NSString* contentType = headers[@"Content-Type"];
        _topReader = [[CBLMultipartReader alloc] initWithContentType: contentType
                                                            delegate: self];
        if (!_topReader) {
            Warn(@"%@ got invalid Content-Type '%@'", self, contentType);
            [self cancelWithStatus: kCBLStatusUpstreamError];
            return;
        }
    }
    
    [super connection: connection didReceiveResponse: response];
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [super connection: connection didReceiveData: data];
    [_topReader appendData: data];
    if (_topReader.error) {
        [self cancelWithStatus: kCBLStatusUpstreamError];
    }
}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    LogTo(SyncVerbose, @"%@: Finished loading (%u documents)", self, _docCount);
    if (!_topReader.finished) {
        Warn(@"%@ got unexpected EOF", self);
        [self cancelWithStatus: kCBLStatusUpstreamError];
        return;
    }
    
    [self clearConnection];
    [self respondWithResult: self error: nil];
}


#pragma mark - MULTIPART CALLBACKS:


/** This method is called when a part's headers have been parsed, before its data is parsed. */
- (void) startedPart: (NSDictionary*)headers {
    Assert(!_docReader);
    LogTo(SyncVerbose, @"%@: Starting new document; ID=\"%@\"", self, headers[@"X-Doc-ID"]);
    _docReader = [[CBLMultipartDocumentReader alloc] initWithDatabase: _db];
    _docReader.headers = headers;
}

/** This method is called to append data to a part's body. */
- (void) appendToPart: (NSData*)data {
    Assert(_docReader);
    if (![_docReader appendData: data])
        [self cancelWithStatus: _docReader.status];
}

/** This method is called when a part is complete. */
- (void) finishedPart {
    LogTo(SyncVerbose, @"%@: Finished document", self);
    Assert(_docReader);
    if (![_docReader finish]) {
        [self cancelWithStatus: _docReader.status];
        return;
    }
    ++_docCount;
    _onDocument(_docReader.document);
    _docReader = nil;
}



@end
