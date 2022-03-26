//
//  CBLConnectedClient.mm
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLConnectedClient.h"
#import "CBLStringBytes.h"
#import "CBLWebSocket.h"
#import "CBLCoreBridge.h"
#import "CBLDocument+Internal.h"
#import "CBLStatus.h"

using namespace fleece;

@interface CBLConnectedClient ()

@property (readonly, nonatomic) dispatch_queue_t dispatchQueue;
@property (nonatomic, weak) void(^getDocCompletion)(CBLDocument* docInfo, NSError* error);
@property (nonatomic, weak) void(^updateDocCompletion)(BOOL success, NSError* error);

@end

@implementation CBLConnectedClient {
    C4ConnectedClient*  _client;
    NSURL*              _url;
    C4Error             _c4err;
}

@synthesize dispatchQueue=_dispatchQueue;
@synthesize getDocCompletion=_getDocCompletion;
@synthesize updateDocCompletion=_updateDocCompletion;

- (instancetype) initWithURL: (NSURL*)url authenticator: (CBLAuthenticator*)authenticator {
    self = [super init];
    
    if (self) {
        _url = url;
        
        NSString* qName = $sprintf(@"ConnectedClient <%@>", url.absoluteString);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        CBLStringBytes sliceURL(_url.absoluteString);
        C4SocketFactory socketFactory = CBLWebSocket.socketFactory;
        socketFactory.context = (__bridge void*)self;
        
        C4ConnectedClientParameters params = {
            .url                = sliceURL,
            .socketFactory      = &socketFactory,
            .callbackContext    = (__bridge void*)self,
        };
        C4Error c4err = {};
        _client = c4client_new(&params, &c4err);
    }
    
    return self;
}

- (void) dealloc {
    c4client_free(_client);
    
    _client = nil;
}

#pragma mark - Start & Stop

// Note: Currently we are not using and exposing this method.
// When connectedClient is created, it will automatically gets created.
// Also in going forward, we will try to avoid exposing start() and stop().
- (void) start {
    c4client_start(_client);
}

- (void) stop {
    c4client_stop(_client);
}

#pragma mark - Get Document

static void getDocumentCallback(C4ConnectedClient* c4client,
                                  const C4DocResponse* doc,
                                  C4Error* err,
                                  void* context) {
    auto client = (__bridge CBLConnectedClient*)context;
    CBLDocument* cblDoc = nil;
    NSError* error = nil;
    if (err == nil || err->code == 0) {
        if (doc->deleted) {
            cblDoc = nil;
            error = [NSError errorWithDomain: CBLErrorDomain
                                        code: CBLErrorNotFound
                                    userInfo: nil];
                
        } else {
            C4HeapSlice body = doc->body;
            FLDict dict = kFLEmptyDict;
            if (body.buf) {
                FLValue docBodyVal = FLValue_FromData(body, kFLTrusted);
                dict = FLValue_AsDict(docBodyVal);
            }
            
            cblDoc = [[CBLDocument alloc] initWithDatabase: nil
                                                documentID: slice2string(doc->docID)
                                                revisionID: slice2string(doc->revID)
                                                      body: dict];
        }
    } else if (err) {
        convertError(*err, &error);
    }
    
    dispatch_async(client->_dispatchQueue, ^{
        client.getDocCompletion(cblDoc, error);
    });
}

- (void) documentWithID: (NSString*)identifier
             completion: (void (^)(CBLDocument*, NSError*))completion {
    CBLStringBytes docID(identifier);
    _c4err = {};
    self.getDocCompletion = completion;
    
    c4client_getDoc(_client, docID, nullslice, nullslice, true,
                    &getDocumentCallback, (__bridge void*)self, &_c4err);
}

#pragma mark - Save

- (BOOL) saveDocument: (CBLMutableDocument *)document
           completion: (void (^)(BOOL success, NSError*))completion
                error: (NSError**)error {
    Assert(document.isMutable);
    return [self saveDocument: document asDeletion: NO completion: completion error: error];
}

- (BOOL) deleteDocument: (CBLDocument *)document
             completion: (void (^)(BOOL success, NSError*))completion
                  error: (NSError**)error {
    return [self saveDocument: document asDeletion: YES completion: completion error: error];
}

static void updateDocumentCallback(C4ConnectedClient* c4client, C4Error* err, void *context) {
    auto client = (__bridge CBLConnectedClient*)context;
    BOOL success = err == nil || err->code == 0;
    NSError* error = nil;
    if (!success && err) {
        convertError(*err, &error);
    }
    dispatch_async(client->_dispatchQueue, ^{
        client.updateDocCompletion(success, error);
    });
}

- (BOOL) saveDocument: (CBLDocument*)document
           asDeletion: (BOOL)deletion
           completion: (void (^)(BOOL success, NSError*))completion
                error: (NSError**)outError {
    self.updateDocCompletion = completion;
    
    C4RevisionFlags revFlags = 0;
    if (deletion)
        revFlags = kRevDeleted;
    FLSliceResult body;
    if (!deletion && !document.isEmpty) {
        // Encode properties to Fleece data:
        body = [document encodeWithRevFlags: &revFlags shared: NO error: outError];
        if (!body.buf) {
            return NO;
        }
    } else {
        FLEncoder enc = FLEncoder_New();
        FLEncoder_BeginDict(enc, 0);
        FLEncoder_EndDict(enc);
        auto result = FLEncoder_Finish(enc, nullptr);
        FLEncoder_Free(enc);
        
        body = result;
    }
    
    // Save to database:
    C4Error err;
    CBLStringBytes docID(document.id);
    CBLStringBytes revID(document.revisionID); // make sure, this is nullslice when no revisionID present
    c4client_updateDoc(_client,
                       docID,
                       nullslice,
                       revID,
                       revFlags,
                       (FLSlice)body,
                       &updateDocumentCallback,
                       (__bridge void*)self,
                       &err);
    
    FLSliceResult_Release(body);
    
    if (err)
        return convertError(err, outError);
    
    return YES;
}

@end
