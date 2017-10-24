//
//  CBLFragment.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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


- (NSInteger) integerValue {
    if (_key)
        return [_parent integerForKey: _key];
    else
        return [_parent integerAtIndex: _index];
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


- (NSObject*) object {
    return self.value;
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


- (NSObject*) value {
    if (_key)
        return [_parent objectForKey: _key];
    else
        return [_parent objectAtIndex: _index];
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
