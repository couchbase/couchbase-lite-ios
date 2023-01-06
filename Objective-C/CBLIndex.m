//
//  CBLIndex.m
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

#import "CBLIndex+Internal.h"
#import "CBLJSON.h"

@implementation CBLIndex

@synthesize indexType=_indexType, queryLanguage=_queryLanguage;

- (instancetype) initWithIndexType: (C4IndexType)indexType
                     queryLanguage: (C4QueryLanguage)language {
    self = [super init];
    if (self) {
        _indexType = indexType;
        _queryLanguage = language;
    }
    return self;
}

- (instancetype) initWithIndexType: (C4IndexType)indexType {
    return [self initWithIndexType: indexType queryLanguage: kC4JSONQuery];
}

- (id) getJSON {
    // Implement by subclass
    [NSException raise: NSInternalInconsistencyException
                format: @"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
    return nil;
}

- (NSString*) getIndexSpecs {
    NSError* error = nil;
    NSString* json = [CBLJSON stringWithJSONObject: self.getJSON options: 0 error: &error];
    Assert(json, @"Error failed to decode JSON string %@", error);
    return json;
}

- (C4IndexOptions) indexOptions {
    // default empty options
    return (C4IndexOptions){ };
}

@end

