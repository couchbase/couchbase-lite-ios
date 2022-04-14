//
//  CBLRemoteDatabase.mm
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

#import "CBLRemoteDatabase.h"
#import "CBLStringBytes.h"
#import "CBLWebSocket.h"
#import "CBLCoreBridge.h"
#import "CBLDocument+Internal.h"
#import "CBLStatus.h"
#import "CBLRemoteDatabase+Internal.h"

using namespace fleece;

@interface CBLRemoteDatabase ()

@property (readonly, nonatomic) dispatch_queue_t dispatchQueue;
@property (nonatomic) NSMutableArray* contexts;

@end

@implementation CBLRemoteDatabase {
    C4ConnectedClient*  _client;
    NSURL*              _url;
    C4Error             _c4err;
}

@synthesize dispatchQueue=_dispatchQueue, contexts=_contexts;

- (instancetype) initWithURL: (NSURL*)url authenticator: (CBLAuthenticator*)authenticator {
    self = [super init];
    
    if (self) {
        _url = url;
        
        NSString* qName = $sprintf(@"ConnectedClient <%@>", url.absoluteString);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        CBLStringBytes sliceURL(_url.absoluteString);
        C4SocketFactory socketFactory = CBLWebSocket.socketFactory;
        socketFactory.context = (__bridge void*)self;
        
        _contexts = [NSMutableArray array];
        
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

#pragma mark - Stop

- (void) stop {
    c4client_stop(_client);
}

#pragma mark - Get Document

static void getDocumentCallback(C4ConnectedClient* c4client,
                                  const C4DocResponse* doc,
                                  C4Error* err,
                                  void* context) {
    ConnectedClientGetDocumentContext* ctx = (__bridge ConnectedClientGetDocumentContext*)context;
    CBLDocument* cblDoc = nil;
    NSError* error = nil;
    if (err == nil || err->code == 0) {
        if (doc->deleted) {
            cblDoc = nil;
            error = [NSError errorWithDomain: CBLErrorDomain
                                        code: CBLErrorNotFound
                                    userInfo: nil];
                
        } else {
            FLSliceResult res = FLSliceResult(alloc_slice(doc->body));
            cblDoc = [[CBLDocument alloc] initWithDocumentID: slice2string(doc->docID)
                                                  revisionID: slice2string(doc->revID)
                                                        body: res];
            FLSliceResult_Release(res);
        }
    } else if (err) {
        convertError(*err, &error);
    }
    
    dispatch_async(ctx.remoteDB.dispatchQueue, ^{
        ctx.docGetCompletion(cblDoc, error);
        [ctx.remoteDB.contexts removeObject: ctx];
    });
}

- (void) documentWithID: (NSString*)identifier
             completion: (void (^)(CBLDocument*, NSError*))completion {
    CBLStringBytes docID(identifier);
    _c4err = {};
    ConnectedClientGetDocumentContext* ctx = [[ConnectedClientGetDocumentContext alloc] initWithRemoteDB: self
                                                                                            completion: completion];
    [_contexts addObject: ctx];
    c4client_getDoc(_client, docID, nullslice, nullslice, true, &getDocumentCallback, (__bridge void*)ctx, &_c4err);
}

#pragma mark - Save

- (void) saveDocument: (CBLMutableDocument *)document
           completion: (void (^)(CBLDocument*, NSError*))completion {
    [self saveDocument: document asDeletion: NO updateCompletion: completion deleteCompletion: nil];
}

- (void) deleteDocument: (CBLDocument *)document
             completion: (void (^)(NSError*))completion {
    [self saveDocument: document asDeletion: YES updateCompletion: nil deleteCompletion: completion];
}

static void updateDocumentCallback(C4ConnectedClient* c4client, C4HeapSlice newRevID, C4Error* err, void *context) {
    ConnectedClientPutDocumentContext* ctx = (__bridge ConnectedClientPutDocumentContext*)context;
    NSError* error = nil;
    if (err != nil && err->code != 0) {
        convertError(*err, &error);
    }
    
    CBLDocument* updatedDoc = nil;
    if (!ctx.isDeleted)
        updatedDoc = [[CBLDocument alloc] initWithDocumentID: ctx.docID
                                                  revisionID: slice2string(newRevID)
                                                        body: ctx.docBody];
    dispatch_async(ctx.remoteDB->_dispatchQueue, ^{
        ctx.isDeleted ? ctx.docDeleteCompletion(error) : ctx.docUpdateCompletion(updatedDoc, error);
        [ctx.remoteDB.contexts removeObject: ctx];
    });
}

- (void) saveDocument: (CBLDocument*)document
           asDeletion: (BOOL)deletion
     updateCompletion: (void (^)(CBLDocument*, NSError*))updateCompletion
     deleteCompletion: (void (^)(NSError*))deleteCompletion {
    [document markAsRemoteDoc];
    
    C4RevisionFlags revFlags = 0;
    if (deletion)
        revFlags = kRevDeleted;
    
    FLSliceResult body;
    if (!deletion && !document.isEmpty) {
        // Encode properties to Fleece data:
        // TODO: https://issues.couchbase.com/browse/CBL-2992
        NSError* error = nil;
        body = [document encodeWithRevFlags: &revFlags error: &error];
        if (!body.buf) {
            deletion ? deleteCompletion(error) : updateCompletion(nil, error);
            return;
        }
    } else {
        FLEncoder enc = FLEncoder_New();
        FLEncoder_BeginDict(enc, 0);
        FLEncoder_EndDict(enc);
        auto result = FLEncoder_Finish(enc, nullptr);
        FLEncoder_Free(enc);
        
        body = result;
    }
    
    // Update doc in the remote database
    C4Error err = { };
    CBLStringBytes docID(document.id);
    CBLStringBytes revID(document.revisionID); // make sure, this is nullslice when no revisionID present
    ConnectedClientPutDocumentContext* ctx;
    if (!deletion)
        ctx = [[ConnectedClientPutDocumentContext alloc] initWithRemoteDB: self
                                                                    docID: document.id
                                                                  docBody: body
                                                               completion: updateCompletion];
    else
        ctx = [[ConnectedClientPutDocumentContext alloc] initDeletionWithRemoteDB: self
                                                                       completion: deleteCompletion];
    
    [_contexts addObject: ctx];
    BOOL success = c4client_putDoc(_client,
                                   docID,
                                   nullslice,
                                   revID,
                                   revFlags,
                                   (FLSlice)body,
                                   &updateDocumentCallback,
                                   (__bridge void*)ctx,
                                   &err);
    
    FLSliceResult_Release(body);
    
    if (!success) {
        Assert(err.code != 0);
        NSError* error = nil;
        convertError(err, &error);
        deletion ? deleteCompletion(error) : updateCompletion(nil, error);
    }
}

@end
