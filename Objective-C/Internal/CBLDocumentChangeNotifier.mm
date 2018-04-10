//
//  CBLDocumentChangeNotifier.mm
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

#import "CBLDocumentChangeNotifier.h"
#import "CBLDatabase+Internal.h"
#import "CBLStringBytes.h"


@implementation CBLDocumentChangeNotifier
{
    NSString* _docID;
    CBLDatabase* _db;
    C4DocumentObserver* _obs;
}


- (instancetype) initWithDatabase: (CBLDatabase*)db
                       documentID: (NSString*)documentID
{
    self = [super init];
    if (self) {
        _db = db;
        _docID = documentID;
        CBLStringBytes bDocID(documentID);
        _obs = c4docobs_create(db.c4db, bDocID, docObserverCallback, (__bridge void *)self);
    }
    return self;
}


static void docObserverCallback(C4DocumentObserver* obs, C4Slice docID, C4SequenceNumber seq,
                                void *context)
{
    [(__bridge CBLDocumentChangeNotifier*)context postChange];
}


- (void) postChange {
    [self postChange: [[CBLDocumentChange alloc] initWithDatabase: _db documentID: _docID]];
}


- (void) stop {
    c4docobs_free(_obs);
    _obs = nullptr;
}


- (void) dealloc {
    c4docobs_free(_obs);
}


@end
