//
//  CBLDocumentChange.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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
#import "CBLDocumentChange.h"
#import "CBLDatabase+Internal.h"

@implementation CBLDocumentChange

@synthesize documentID=_documentID, collection=_collection;

- (instancetype) initWithCollection: (CBLCollection*)collection
                         documentID: (NSString*)documentID
{
    self = [super init];
    if (self) {
        _collection = collection;
        _documentID = documentID;
    }
    return self;
}

- (CBLDatabase*) database {
    CBLDatabase* db = _collection.db;
    if (!db)
        return nil;
    
    return db;
}

@end
