//
//  CBLSubdocument.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLSubdocument.h"
#import "CBLArray.h"
#import "CBLDocument+Internal.h"
#import "CBLFleeceDictionary.h"

@implementation CBLSubdocument {
    CBLDictionary* _dict;
}


+ (instancetype) subdocument {
    return [[self alloc] init];
}


- (instancetype) init {
    return [self initWithData: [CBLFleeceDictionary empty]]; // EMPTY DATA
}


- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary {
    self = [self init];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


- /* internal */ (instancetype) initWithData: (id<CBLReadOnlyDictionary>)data {
    self = [super initWithData: data];
    if (self) {
        _dict = [[CBLDictionary alloc] initWithData: data];
    }
    return self;
}


#pragma mark - GETTER


- (nullable id) objectForKey: (NSString*)key {
    return [_dict objectForKey: key];
}


- (BOOL) booleanForKey: (NSString*)key {
    return [_dict booleanForKey: key];
}


- (NSInteger) integerForKey: (NSString*)key {
    return [_dict integerForKey: key];
}


- (float) floatForKey: (NSString*)key {
    return [_dict floatForKey: key];
}


- (double) doubleForKey: (NSString*)key {
    return [_dict doubleForKey: key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return [_dict stringForKey: key];
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return [_dict numberForKey: key];
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [_dict dateForKey: key];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return [_dict blobForKey: key];
}


- (nullable CBLSubdocument*) subdocumentForKey: (NSString*)key {
    return [_dict subdocumentForKey: key];
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    return [_dict arrayForKey: key];
}


- (BOOL) containsObjectForKey: (NSString*)key {
    return [_dict containsObjectForKey: key];
}


- (NSArray*) allKeys {
    return [_dict allKeys];
}


- (NSDictionary<NSString *,id> *) toDictionary {
    return [_dict toDictionary];
}


#pragma mark - SETTER


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    [_dict setObject: value forKey: key];
}


- (void) setBoolean: (BOOL)value forKey: (NSString*)key {
    [_dict setBoolean: value forKey: key];
}


- (void) setInteger: (NSInteger)value forKey: (NSString*)key {
    [_dict setInteger: value forKey: key];
}


- (void) setFloat: (float)value forKey: (NSString*)key {
    [_dict setFloat: value forKey: key];
}


- (void) setDouble: (double)value forKey: (NSString*)key {
    [_dict setDouble: value forKey: key];
}


- (void) setDictionary:(NSDictionary<NSString *,id> *)dictionary {
    [_dict setDictionary: dictionary];
}


#pragma mark - SUBSCRIPTION


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    return [_dict objectForKeyedSubscript: key];
}

#pragma mark - INTERNAL


- (CBLDictionary*)dictionary {
    return _dict;
}


#pragma mark - FLEECE ENCODING


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError**)outError
{
    return [_dict fleeceEncode: encoder database: database error: outError];
}

@end
