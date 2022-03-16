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

using namespace fleece;

@implementation CBLConnectedClient {
    C4ConnectedClient*  _client;
    NSURL*              _url;
    C4Error             _c4err;
}

- (instancetype) initWithURL: (NSURL*)url authenticator: (CBLAuthenticator*)authenticator {
    self = [super init];
    
    if (self) {
        _url = url;
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

static void documentResultCallack(C4ConnectedClient* client, C4DocResponse doc, void* context) {
    NSLog(@"---------------------------------------------");
    NSLog(@">> %@ %@ %@", slice2string(doc.docID), slice2string(doc.revID), slice2string(doc.body));
    NSLog(@"---------------------------------------------");
    
}

- (CBLDocument*) documentWithID: (NSString*)identifier {
    CBLStringBytes docID(identifier);
    _c4err = {};
    c4client_getDoc(_client, docID, nullslice, nullslice, false,
                    &documentResultCallack, (__bridge void*)self, &_c4err);
    return nil;
}

@end
