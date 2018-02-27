//
//  CBLFragment.m
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

#import "CBLFragment.h"
#import "CBLDocument+Internal.h"


@implementation CBLFragment


- /* internal */ (instancetype) initWithParent: (id)parent key: (NSString*)parentKey {
    self = [super init];
    if (self) {
        _parent = parent;
        _key = parentKey;
    }
    return self;
}


- /* internal */ (instancetype) initWithParent: (id)parent index: (NSUInteger)parentIndex {
    self = [super init];
    if (self) {
        _parent = parent;
        _index = parentIndex;
    }
    return self;
}


#pragma mark - GET


- (NSObject*) value {
    if (_key)
        return [_parent valueForKey: _key];
    else
        return [_parent valueAtIndex: _index];
}


- (NSString*) string {
    if (_key)
        return [_parent stringForKey: _key];
    else
        return [_parent stringAtIndex: _index];
}


- (NSNumber*) number {
    if (_key)
        return [_parent numberForKey: _key];
    else
        return [_parent numberAtIndex: _index];
}


- (NSInteger) integerValue {
    if (_key)
        return [_parent integerForKey: _key];
    else
        return [_parent integerAtIndex: _index];
}


- (long long) longLongValue {
    if (_key)
        return [_parent longLongForKey: _key];
    else
        return [_parent longLongAtIndex: _index];
}


- (float) floatValue {
    if (_key)
        return [_parent floatForKey: _key];
    else
        return [_parent floatAtIndex: _index];
}


- (double) doubleValue {
    if (_key)
        return [_parent doubleForKey: _key];
    else
        return [_parent doubleAtIndex: _index];
}


- (BOOL) booleanValue {
    if (_key)
        return [_parent booleanForKey: _key];
    else
        return [_parent booleanAtIndex: _index];
}


- (NSDate*) date {
    if (_key)
        return [_parent dateForKey: _key];
    else
        return [_parent dateAtIndex: _index];
}


- (CBLBlob*) blob {
    if (_key)
        return [_parent blobForKey: _key];
    else
        return [_parent blobAtIndex: _index];
}


- (CBLArray*) array {
    if (_key)
        return [(CBLDictionary*)_parent arrayForKey: _key];
    else
        return [(CBLArray*)_parent arrayAtIndex: _index];
}


- (CBLDictionary*) dictionary {
    if (_key)
        return [(CBLDictionary*)_parent dictionaryForKey: _key];
    else
        return [(CBLArray*)_parent dictionaryAtIndex: _index];
}


#pragma mark - EXISTENCE


- (BOOL) exists {
    return self.value != nil;
}


#pragma mark SUBSCRIPTING


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    NSParameterAssert(key);
    id value = self.value;
    if (![value respondsToSelector: @selector(objectForKeyedSubscript:)])
        return nil;
    _parent = value;
    _key = key;
    return self;
}


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    id value = self.value;
    if (![value respondsToSelector: @selector(objectAtIndexedSubscript:)])
        return nil;
    if (index >= [(CBLArray*)value count])
        return nil;
    _parent = value;
    _index = index;
    _key = nil;
    return self;
}


@end
