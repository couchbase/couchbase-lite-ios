//
//  CBLReadOnlyArray.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyArray.h"
#import "CBLDocument+Internal.h"
#import "CBLCoreBridge.h"

@implementation CBLReadOnlyArray

@synthesize data=_data;

- /* internal */ (instancetype) initWithData: (id<CBLReadOnlyArray>)data {
    self = [super init];
    if (self) {
        _data = data;
    }
    return self;
}


- (nullable id) objectAtIndex: (NSUInteger)index {
    return [_data objectAtIndex: index];
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    return [_data booleanAtIndex: index];
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    return [_data integerAtIndex: index];
}


- (float) floatAtIndex: (NSUInteger)index {
    return [_data floatAtIndex: index];
}


- (double) doubleAtIndex: (NSUInteger)index {
    return [_data doubleAtIndex: index];
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    return [_data stringAtIndex: index];
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    return [_data numberAtIndex: index];
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return [_data dateAtIndex: index];
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    return [_data blobAtIndex: index];
}


- (CBLReadOnlySubdocument*) subdocumentAtIndex: (NSUInteger)index {
    return [_data subdocumentAtIndex: index];
}


- (CBLReadOnlyArray*) arrayAtIndex: (NSUInteger)index {
    return [_data arrayAtIndex: index];
}


- (NSUInteger) count {
    return [_data count];
}


- (NSArray*) toArray {
    NSMutableArray* array = [NSMutableArray array];
    NSUInteger count = self.count;
    for (NSUInteger i = 0; i < count; i++) {
        id value = [self objectAtIndex: i];
        if ([value conformsToProtocol: @protocol(CBLReadOnlyDictionary)])
            value = [value toDictionary];
        else if ([value conformsToProtocol: @protocol(CBLReadOnlyArray)])
            value = [value toArray];
        [array addObject: value];
    }
    return array;
}


#pragma mark - SUBSCRIPTION


- (CBLReadOnlyFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    id value = index < self.count ? [self objectAtIndex: index] : nil;
    return [[CBLReadOnlyFragment alloc] initWithValue: value];
}


#pragma mark - INTERNAL


- (void) setData: (id <CBLReadOnlyArray>)data {
    _data = data;
}


#pragma mark - FLEECE ENCODABLE


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError**)outError
{
    NSUInteger count = self.count;
    FLEncoder_BeginArray(encoder, count);
    for (NSUInteger i = 0; i < count; i++) {
        id value = [self objectAtIndex: i];
        if (!value) value = [NSNull null];
        if ([value conformsToProtocol: @protocol(CBLFleeceEncodable)]) {
            if (![value fleeceEncode: encoder database: database error: outError])
                return NO;
        } else
           FLEncoder_WriteNSObject(encoder, value);
    }
    FLEncoder_EndArray(encoder);
    return YES;
}

@end
