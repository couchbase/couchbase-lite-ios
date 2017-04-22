//
//  CBLReadOnlyFragment.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyFragment.h"
#import "CBLBlob.h"
#import "CBLJSON.h"
#import "CBLReadOnlyArray.h"
#import "CBLReadOnlySubdocument.h"

@implementation CBLReadOnlyFragment {
    id _value;
}

- /* internal */ (instancetype) initWithValue: (id)value {
    self = [super init];
    if (self) {
        _value = value;
    }
    return self;
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
    // TODO:
    return [$castIf(NSNumber, _value) boolValue];
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


- (CBLReadOnlyArray*) array {
    return $castIf(CBLReadOnlyArray, _value);
}


- (CBLReadOnlySubdocument*) subdocument {
    return $castIf(CBLReadOnlySubdocument, _value);
}


- (NSObject*) value {
    return _value;
}


#pragma mark - EXISTENCE


- (BOOL) exists {
    return _value != nil;
}


#pragma mark SUBSCRIPTION


- (CBLReadOnlyFragment*) objectForKeyedSubscript: (NSString*)key {
    if ([_value conformsToProtocol: @protocol(CBLReadOnlyDictionary)])
        return [_value objectForKeyedSubscript: key];
    return [[CBLReadOnlyFragment alloc] initWithValue: nil];
}


- (CBLReadOnlyFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    if ([_value conformsToProtocol: @protocol(CBLReadOnlyArray)])
        return [_value objectAtIndexedSubscript: index];
    return [[CBLReadOnlyFragment alloc] initWithValue: nil];
}


@end
