//
//  CBLCollectionConfiguration.m
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
#import "CBLCollectionConfiguration.h"
#import "CBLCollection+Internal.h"
#import "CBLPrecondition.h"

@implementation CBLCollectionConfiguration

@synthesize collection=_collection;
@synthesize documentIDs=_documentIDs, channels=_channels;
@synthesize pushFilter=_pushFilter, pullFilter=_pullFilter;
@synthesize conflictResolver=_conflictResolver;

- (instancetype) initWithCollection: (CBLCollection*)collection {
    self = [super init];
    if (self) {
        _collection = collection;
    }
    return self;
}

- (instancetype) initWithConfig: (CBLCollectionConfiguration*)config {
    self = [super init];
    if (self) {
        _collection = config.collection;
        _documentIDs = config.documentIDs;
        _channels = config.channels;
        _pushFilter = config.pushFilter;
        _pullFilter = config.pullFilter;
        _conflictResolver = config.conflictResolver;
    }
    return self;
}

+ (NSArray<CBLCollectionConfiguration*>*) fromCollections: (NSArray<CBLCollection*>*)collections {
    [CBLPrecondition assertArrayNotEmpty: collections name: @"collections"];
    NSMutableArray* configs = [NSMutableArray arrayWithCapacity: collections.count];
    for (CBLCollection* collection in collections) {
        [configs addObject: [[CBLCollectionConfiguration alloc] initWithCollection: collection]];
    }
    return configs;
}

+ (NSArray<CBLCollectionConfiguration*>*) fromCollections:(NSArray<CBLCollection*>*)collections
                                                   config:(void (^)(CBLCollectionConfiguration* config))config {
    [CBLPrecondition assertArrayNotEmpty:collections name:@"collections"];
    NSMutableArray* configs = [NSMutableArray arrayWithCapacity:collections.count];
    for (CBLCollection* collection in collections) {
        CBLCollectionConfiguration* colConfig = [[CBLCollectionConfiguration alloc] initWithCollection:collection];
        if (config) {
            config(colConfig);
        }
        [configs addObject:colConfig];
    }
    return configs;
}

- (NSDictionary*) effectiveOptions {
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    options[@kC4ReplicatorOptionChannels] = self.channels;
    options[@kC4ReplicatorOptionDocIDs] = self.documentIDs;
    return options;
}

@end
