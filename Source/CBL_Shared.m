//
//  CBL_Shared.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/20/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Shared.h"
#import "CBL_Server.h"


@implementation CBL_Shared
{
    NSMutableDictionary* _databases;
    CBL_Server* _backgroundServer;
}

@synthesize backgroundServer=_backgroundServer;

- (id)init {
    self = [super init];
    if (self) {
        _databases = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void) dealloc
{
    [_backgroundServer close];
}

- (void) setValue: (id)value
          forType: (NSString*)type
             name: (NSString*)name
  inDatabaseNamed: (NSString*)dbName
{
    @synchronized(self) {
        NSMutableDictionary* dbDict = _databases[dbName];
        if (!dbDict)
            dbDict = _databases[dbName] = [NSMutableDictionary dictionary];
        NSMutableDictionary* typeDict = dbDict[type];
        if (!typeDict)
            typeDict = dbDict[type] = [NSMutableDictionary dictionary];
        [typeDict setValue: value forKey: name];
    }
}

- (id) valueForType: (NSString*)type
               name: (NSString*)name
    inDatabaseNamed: (NSString*)dbName
{
    @synchronized(self) {
        return _databases[dbName][type][name];
    }
}

- (bool) hasValuesOfType: (NSString*)type
         inDatabaseNamed: (NSString*)dbName
{
    return [_databases[dbName][type] count] > 0;
}

- (NSDictionary*) valuesOfType: (NSString*)type
               inDatabaseNamed: (NSString*)dbName
{
    @synchronized(self) {
        return [_databases[dbName][type] copy];
    }
}

- (void) forgetDatabaseNamed: (NSString*)name {
    @synchronized(self) {
        [_databases removeObjectForKey: name];
    }
}

@end
