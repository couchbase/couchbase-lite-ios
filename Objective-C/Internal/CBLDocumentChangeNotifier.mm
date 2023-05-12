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

#import "CBLCollection+Internal.h"
#import "CBLDocumentChangeNotifier.h"
#import "CBLDatabase+Internal.h"
#import "CBLStringBytes.h"

@implementation CBLDocumentChangeNotifier
{
    NSString* _docID;
    C4DocumentObserver* _obs;
    NSString* _collectionName;
}

@synthesize collection=_collection;

- (instancetype) initWithCollection: (CBLCollection*)collection
                         documentID: (NSString*)documentID
{
    self = [super init];
    if (self) {
        _collection = collection;
        _collectionName = collection.fullName;
        _docID = documentID;
        CBLStringBytes bDocID(documentID);
        C4Error c4err = {};
        _obs = c4docobs_createWithCollection(collection.c4col,
                                             bDocID,
                                             docObserverCallback,
                                             (__bridge void *)self,
                                             &c4err);
        if (!_obs) {
            CBLWarn(Database, @"%@ Failed to create document change observer for document '%@' "
                                "in collection '%@' with error '%d/%d'",
                    self, _docID, _collectionName, c4err.domain, c4err.code);
        }
    }
    return self;
}

static void docObserverCallback(C4DocumentObserver* obs, C4Collection* collection,
                                C4Slice docID, C4SequenceNumber seq, void *context)
{
    [(__bridge CBLDocumentChangeNotifier*)context postChange];
}

- (void) postChange {
    CBLCollection* collection = _collection;
    if (!collection) {
        CBLWarn(Database, @"%@ Unnable to notify a change for document '%@' in collection '%@' "
                           "as the collection has been released", self, _collectionName, _docID);
        return;
    }
    
    NSError* error = nil;
    CBLDocumentChange* change = [[CBLDocumentChange alloc] initWithCollection: collection
                                                                   documentID: _docID
                                                                        error: &error];
    if (!change) {
        CBLWarn(Database, @"%@ Unable to notify a change for document '%@' in collection '%@' : %@",
                self, _docID, collection.fullName, error);
        return;
    }
    
    [self postChange: change];
}

- (void) stop {
    c4docobs_free(_obs);
    _obs = nullptr;
}

- (void) dealloc {
    c4docobs_free(_obs);
}

@end
