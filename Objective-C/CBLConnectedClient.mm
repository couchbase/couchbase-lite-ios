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
#include "CBLDocument+Internal.h"

using namespace fleece;

@interface CBLConnectedClient ()

@property (readonly, nonatomic) dispatch_queue_t dispatchQueue;
@property (nonatomic, weak) void(^getDocCompletion)(CBLDocumentInfo* nullable);

@end

@implementation CBLConnectedClient {
    C4ConnectedClient*  _client;
    NSURL*              _url;
    C4Error             _c4err;
}

@synthesize dispatchQueue=_dispatchQueue;
@synthesize getDocCompletion=_getDocCompletion;

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
        _client = c4client_new(params, &c4err);
    }
    
    return self;
}

- (void) dealloc {
    c4client_free(_client);
    
    _client = nil;
}

static void documentResultCallack(C4ConnectedClient* c4client, C4DocResponse doc, void* context) {
    auto client = (__bridge CBLConnectedClient*)context;
    auto cblDoc = [[CBLDocumentInfo alloc] initWithID: slice2string(doc.docID)
                                                revID: slice2string(doc.revID)
                                                 body: doc.body];
    dispatch_async(client->_dispatchQueue, ^{
        client.getDocCompletion(cblDoc);
    });
}

- (void) documentWithID: (NSString*)identifier completion: (void (^)(CBLDocumentInfo* nullable))completion {
    CBLStringBytes docID(identifier);
    _c4err = {};
    self.getDocCompletion = completion;
    
    c4client_getDoc(_client, docID, nullslice, nullslice, true,
                    &documentResultCallack, (__bridge void*)self, &_c4err);
}

- (void) start {
    c4client_start(_client);
}

- (void) stop {
    c4client_stop(_client);
}

@end
