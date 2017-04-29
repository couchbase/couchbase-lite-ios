//
//  CBLReadOnlyDictionary.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyDictionary.h"
#import "CBLCoreBridge.h"
#import "CBLDocument+Internal.h"
#import "CBLStringBytes.h"


@implementation CBLReadOnlyDictionary {
    id <CBLReadOnlyDictionary> _data; // nullable
}

@synthesize data=_data;


- /* internal */ (instancetype) initWithData: (id <CBLReadOnlyDictionary>)data {
    self = [super init];
    if (self) {
        _data = data;
    }
    return self;
}


- (NSUInteger) count {
    return _data.count;
}


- (nullable id) objectForKey: (NSString*)key {
    return [_data objectForKey: key];
}


- (BOOL) booleanForKey: (NSString*)key {
    return [_data booleanForKey: key];
}


- (NSInteger) integerForKey: (NSString*)key {
    return [_data integerForKey: key];
}


- (float) floatForKey: (NSString*)key {
    return [_data floatForKey: key];
}


- (double) doubleForKey: (NSString*)key {
    return [_data doubleForKey: key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return [_data stringForKey: key];
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return [_data numberForKey: key];
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [_data dateForKey: key];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return [_data blobForKey: key];
}


- (nullable CBLReadOnlySubdocument*) subdocumentForKey: (NSString*)key {
    return [_data subdocumentForKey: key];
}


- (nullable CBLReadOnlyArray*) arrayForKey: (NSString*)key {
    return [_data arrayForKey: key];
}


- (BOOL) containsObjectForKey: (NSString*)key {
    return [_data containsObjectForKey: key];
}


- (NSArray*) allKeys {
    return [_data allKeys];
}


- (NSDictionary<NSString*,id>*) toDictionary {
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    NSArray* keys = [self allKeys];
    for (NSString* key in keys) {
        id value = [self objectForKey: key];
        if ([value conformsToProtocol: @protocol(CBLReadOnlyDictionary)])
            value = [value toDictionary];
        else if ([value conformsToProtocol: @protocol(CBLReadOnlyArray)])
            value = [value toArray];
        dict[key] = value;
    }
    return dict;
}


#pragma mark - SUBSCRIPTION


- (CBLReadOnlyFragment*) objectForKeyedSubscript: (NSString*)key {
    return [[CBLReadOnlyFragment alloc] initWithValue: [self objectForKey: key]];
}


#pragma mark - INTERNAL


- (void) setData: (id<CBLReadOnlyDictionary>)data {
    _data = data;
}


- (BOOL) isEmpty {
    return _data.count == 0;
}



#pragma mark - FLEECE ENCODING


- (BOOL) isFleeceEncodableValue: (id)value {
    return YES;
}


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError**)outError
{
    NSArray* keys = [self allKeys];
    FLEncoder_BeginDict(encoder, keys.count);
    for (NSString* key in keys) {
        CBLStringBytes bKey(key);
        FLEncoder_WriteKey(encoder, bKey);
        id value = [self objectForKey: key];
        if ([self isFleeceEncodableValue: value]) {
            if ([value conformsToProtocol: @protocol(CBLFleeceEncodable)]){
                if (![value fleeceEncode: encoder database: database error: outError])
                    return NO;
            } else
                FLEncoder_WriteNSObject(encoder, value);
        }
    }
    FLEncoder_EndDict(encoder);
    return YES;
}


@end
