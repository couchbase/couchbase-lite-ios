//
//  CBLFragment.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFragment.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"

@implementation CBLFragment {
    id _value;
    id _parent;
    id _parentKey;
    NSUInteger _index;
}


- /* internal */ (instancetype) initWithValue: (id)value parent: (id)parent parentKey: (id)parentKey {
    self = [super initWithValue: value];
    if (self) {
        _value = value;
        _parent = parent;
        _parentKey = parentKey;
    }
    return self;
}


#pragma mark - SUBSCRIPTION


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    if ([_value conformsToProtocol: @protocol(CBLDictionary)])
        return [_value objectForKeyedSubscript: key];
    return [[CBLFragment alloc] initWithValue: nil parent: nil parentKey: nil];
}


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    if ([_value conformsToProtocol: @protocol(CBLArray)])
        return [_value objectAtIndexedSubscript: index];
    return [[CBLFragment alloc] initWithValue: nil parent: nil parentKey: nil];
}


#pragma mark - SET


- (void) setValue: (NSObject*)value {
    if ([_parent conformsToProtocol: @protocol(CBLDictionary)]) {
        NSString* key = (NSString*)_parentKey;
        [_parent setObject: value forKey: key];
        _value = [_parent objectForKey: key];
    } else if ([_parent conformsToProtocol: @protocol(CBLArray)]) {
        NSInteger index = [_parentKey integerValue];
        @try {
            [_parent setObject: value atIndex: index];
            _value = [_parent objectAtIndex: index];
        } @catch (NSException *exception) { }
    }
}


#pragma mark - GET


- (NSInteger) integerValue {
    return [$castIf(NSNumber, _value) integerValue];
}


- (float) floatValue {
    return [$castIf(NSNumber, _value) floatValue];
}


- (double) doubleValue {
    return [$castIf(NSNumber, _value) doubleValue];
}


- (BOOL) boolValue {
    return [CBLData booleanValueForObject: _value];
}


- (NSObject*) object {
    return _value;
}


- (NSString*) string {
    return $castIf(NSString, _value);
}


- (NSNumber*) number {
    return $castIf(NSNumber, _value);
}


- (NSDate*) date {
    return [CBLJSON dateWithJSONObject: self.string];
}


- (CBLBlob*) blob {
    return $castIf(CBLBlob, _value);
}


- (CBLArray*) array {
    return $castIf(CBLArray, _value);
}


- (CBLSubdocument*) subdocument {
    return $castIf(CBLSubdocument, _value);
}


- (NSObject*) value {
    return _value;
}


#pragma mark - EXISTENCE


- (BOOL) exists {
    return _value != nil;
}


@end
