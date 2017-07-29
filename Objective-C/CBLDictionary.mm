//
//  CBLDictionary.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDictionary.h"
#import "CBLDictionary+Swift.h"
#import "CBLArray.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLFragment.h"
#import "CBLJSON.h"
#import "CBLStringBytes.h"


@implementation CBLDictionary {
    NSMutableDictionary<NSString*, id>* _dict;
    NSMapTable* _changeListeners;
    NSArray* _keys; // key cache
    NSObject* _lock;
}


@synthesize changed=_changed, swiftObject=_swiftObject;


+ (instancetype) dictionary {
    return [[self alloc] init];
}


- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLDict*)data {
    self = [super initWithFleeceData: data];
    if (self) {
        _lock = [[NSObject alloc] init];
    }
    return self;
}

- (instancetype) init {
    return [self initWithFleeceData: nil];
}


- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary {
    self = [self initWithFleeceData: nil];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


#pragma mark - GETTER


- (NSUInteger) count {
    CBL_LOCK(_lock) {
        if (!_changed)
            return super.count;
        
        __block NSUInteger count = _dict.count;
        for (NSString* key in super.keys) {
            if (!_dict[key])
                count += 1;
        }
        
        [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
            if (value == kCBLRemovedValue)
                count -= 1;
        }];
        return count;
    }
}


- (NSArray*) keys {
    CBL_LOCK(_lock) {
        if (_keys)
            return _keys;
        
        NSArray* superKeys = super.keys;
        if (!_changed)
            return superKeys;
        
        if (superKeys.count == 0) {
            _keys = _dict.allKeys;
        } else {
            NSMutableSet* result = [NSMutableSet setWithArray: superKeys];
            [_dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
                if (value != kCBLRemovedValue)
                    [result addObject: key];
                else
                    [result removeObject: key];
            }];
            _keys = result.allObjects;
        }
        return _keys;
    }
}


- (nullable id) objectForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        id value = _dict[key];
        if (!value) {
            value = [super objectForKey: key];
            if ([value isKindOfClass: [CBLReadOnlyDictionary class]]) {
                value = [value cbl_toCBLObject];
                [self setValue: value forKey: key isChange: NO];
            } else if ([value isKindOfClass: [CBLReadOnlyArray class]]) {
                value = [value cbl_toCBLObject];
                [self setValue: value forKey: key isChange: NO];
            }
        } else if (value == kCBLRemovedValue)
            value = nil;
        return value;
    }
}


- (BOOL) booleanForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        id value = _dict[key];
        if (!value)
            return [super booleanForKey: key];
        else {
            if (value == kCBLRemovedValue)
                return NO;
            else
                return [CBLData booleanValueForObject: value];
        }
    }
}


- (NSInteger) integerForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        id value = _dict[key];
        if (!value)
            return [super integerForKey: key];
        else
            return [$castIf(NSNumber, value) integerValue];
    }
}


- (float) floatForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        id value = _dict[key];
        if (!value)
            return [super floatForKey: key];
        else
            return [$castIf(NSNumber, value) floatValue];
    }
}


- (double) doubleForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        id value = _dict[key];
        if (!value)
            return [super doubleForKey: key];
        else
            return [$castIf(NSNumber, value) doubleValue];
    }
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return $castIf(NSString, [self objectForKey: key]);
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return $castIf(NSNumber, [self objectForKey: key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [CBLJSON dateWithJSONObject: [self objectForKey: key]];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return $castIf(CBLBlob, [self objectForKey:key]);
}


- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key {
    return $castIf(CBLDictionary, [self objectForKey: key]);
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    return $castIf(CBLArray, [self objectForKey: key]);
}


- (BOOL) containsObjectForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        id value = _dict[key];
        if (!value)
            return [super containsObjectForKey: key];
        else
            return value != kCBLRemovedValue;
    }
}


- (NSDictionary<NSString*,id>*) toDictionary {
    CBL_LOCK(_lock) {
        NSDictionary* backingData = [super toDictionary];
        if (_dict.count == 0)
            return backingData; // No changes
        
        NSMutableDictionary* result = [backingData mutableCopy];
        [_dict enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
            if (value == kCBLRemovedValue)
                result[key] = nil; // Remove key
            else
                result[key] = [value cbl_toPlainObject];
        }];
        return result;
    }
}


- (id) cbl_toCBLObject {
    return self;
}


#pragma mark - SETTER


- (void) setDictionary: (nullable NSDictionary<NSString*,id>*)dictionary {
    NSArray* inheritedKeys = [super keys];
    NSUInteger capacity = MAX(dictionary.count, inheritedKeys.count);
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: capacity];

    [dictionary enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        result[key] = [value cbl_toCBLObject];
    }];
    
    // Mark pre-existing keys as removed by setting the value to kRemovedValue:
    for (NSString* key in inheritedKeys) {
        if (!result[key])
            result[key] = kCBLRemovedValue;
    };
    
    CBL_LOCK(_lock) {
        _dict = result;
        [self setChanged];
    }
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    CBL_LOCK(_lock) {
        if (!value) value = [NSNull null]; // nil conversion only for apple platform
        id oldValue = [self objectForKey: key];
        value = [value cbl_toCBLObject];
        if (!$equal(value, oldValue)) {
            [self setValue: value forKey: key isChange: YES];
            _keys = nil; // Reset key cache
        }
    }
}


- (void) removeObjectForKey:(NSString *)key {
    CBL_LOCK(_lock) {
        id value = [super containsObjectForKey: key] ? kCBLRemovedValue : nil;
        if (value != _dict[key]) {
            [self setValue: value forKey: key isChange: YES];
            _keys = nil; // Reset key cache
        }
    }
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    CBL_LOCK(_lock) {
        if (!_changed)
            return [super countByEnumeratingWithState: state objects: buffer count: len];
        else
            return [[self keys] countByEnumeratingWithState: state objects: buffer count: len];
    }
}


#pragma mark - SUBSCRIPTING


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    id value = [self objectForKey: key];
    return [[CBLFragment alloc] initWithValue: value parent: self parentKey: key];
}


#pragma mark - INTERNAL


- (BOOL) isEmpty {
    CBL_LOCK(_lock) {
        if (!_changed)
            return super.isEmpty;
        
        for (NSString* key in super.keys) {
            if (!_dict[key])
                return NO;
        }
        
        __block BOOL isEmpty = YES;
        [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
            if (value != kCBLRemovedValue) {
                isEmpty = NO;
                *stop = YES;
            }
        }];
        return isEmpty;
    }
}


#pragma mark - PRIVATE


- (void) setValue: (id)value forKey: (NSString*)key isChange: (BOOL)isChange {
    //  This method is always called under _lock.
    if (!_dict)
        _dict = [NSMutableDictionary dictionary];
    
    _dict[key] = value;
    if (isChange)
        [self setChanged];
}


#pragma mark - CHANGE


- (void) setChanged {
    //  This is always called under _lock.
    if (!_changed) {
        _changed = YES;
    }
}


- (BOOL) changed {
    CBL_LOCK(_lock) {
        return _changed;
    }
}


#pragma mark - FLEECE ENCODABLE


- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError
{
    CBL_LOCK(_lock) {
        NSArray* keys = self.keys;
        FLEncoder_BeginDict(encoder, keys.count);
        for (NSString* key in keys) {
            id value = [self objectForKey: key];
            if (value != kCBLRemovedValue) {
                CBLStringBytes bKey(key);
                FLEncoder_WriteKey(encoder, bKey);
                if (![value cbl_fleeceEncode: encoder database: database error: outError])
                    return NO;
            }
        }
        FLEncoder_EndDict(encoder);
        return YES;
    }
}


@end
