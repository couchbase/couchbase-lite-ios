//
//  CBLDatabaseChange.m
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

#import "CBLDatabaseChange.h"
#import "CBLDatabase+Internal.h"

@implementation CBLDatabaseChange

@synthesize database=_database, documentIDs=_documentIDs, isExternal=_isExternal;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                      documentIDs: (NSArray *)documentIDs
                       isExternal: (BOOL)isExternal
{
    self = [super init];
    if (self) {
        _database = database;
        _documentIDs = documentIDs;
        _isExternal = isExternal;
    }
    return self;
}

@end
