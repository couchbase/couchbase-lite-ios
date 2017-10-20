//
//  CBLReadOnlyDictionary.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyDictionary.h"
#import "CBLReadOnlyDictionary+Swift.h"
#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "CBLStringBytes.h"
#import "PlatformCompat.hh"
#import "CBLFleece.hh"
#import "MDict.hh"
#import "MDictIterator.hh"

using namespace cbl;
using namespace fleeceapi;


@implementation CBLReadOnlyDictionary
{
    NSArray* _keys;
}


@synthesize swiftObject=_swiftObject;



- (instancetype) initEmpty {
    return [super init];
}


- (instancetype) initWithMValue: (fleeceapi::MValue<id>*)mv
                       inParent: (fleeceapi::MCollection<id>*)parent
{
    self = [super init];
    if (self) {
        _dict.initInSlot(mv, parent);
    }
    return self;
}


- (instancetype) initWithCopyOfMDict: (const MDict<id>&)mDict
                           isMutable: (bool)isMutable
{
    self = [super init];
    if (self) {
        _dict.initAsCopyOf(mDict, isMutable);
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


- (CBLDictionary*) mutableCopyWithZone:(NSZone *)zone {
    return [[CBLDictionary alloc] initWithCopyOfMDict: _dict isMutable: true];
}


- (void) fl_encodeToFLEncoder: (FLEncoder)enc {
    Encoder encoder(enc);
    _dict.encodeTo(encoder);
    encoder.release();
}


- (MCollection<id>*) fl_collection {
    return &_dict;
}


#pragma mark - Counting Entries


- (NSUInteger) count {
    return _dict.count();
}


#pragma mark - Accessing Keys


- (NSArray*) keys {
    // I cache the keys array because my -countByEnumeratingWithState method delegates to it,
    // but it's not actually retained by anything related to the enumeration, so it's otherwise
    // possible for the array to be dealloced while the enumeration is going on.
    if (!_keys) {
        NSMutableArray* keys = [NSMutableArray arrayWithCapacity: _dict.count()];
        for (MDict<id>::iterator i(_dict); i; ++i)
            [keys addObject: i.nativeKey()];
        _keys = keys;
    }
    return _keys;
}


- (void) keysChanged {
    // My subclass CBLDictionary calls this when it's mutated, to invalidate the array
    _keys = nil;
}


#pragma mark - Type Getters


static const MValue<id>& _get(MDict<id> &dict, NSString* key) {
    CBLStringBytes keySlice(key);
    return dict.get(keySlice);
}


static id _getObject(MDict<id> &dict, NSString* key, Class asClass =nil) {
    //OPT: Can return nil before calling asNative, if MValue.value exists and is wrong type
    id obj = _get(dict, key).asNative(&dict);
    if (asClass && ![obj isKindOfClass: asClass])
        obj = nil;
    return obj;
}


- (nullable CBLReadOnlyArray*) arrayForKey: (NSString*)key {
    return _getObject(_dict, key, [CBLReadOnlyArray class]);
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return _getObject(_dict, key, [CBLBlob class]);
}


- (BOOL) booleanForKey: (NSString*)key {
    return asBool(_get(_dict, key), _dict);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return asDate(_getObject(_dict, key, nil));
}


- (nullable CBLReadOnlyDictionary*) dictionaryForKey: (NSString*)key {
    return _getObject(_dict, key, [CBLReadOnlyDictionary class]);
}


- (nullable id) objectForKey: (NSString*)key {
    return _getObject(_dict, key, nil);
}


- (double) doubleForKey: (NSString*)key {
    return asDouble(_get(_dict, key), _dict);
}


- (float) floatForKey: (NSString*)key {
    return asFloat(_get(_dict, key), _dict);
}


- (NSInteger) integerForKey: (NSString*)key {
    return asInteger(_get(_dict, key), _dict);
}


- (long long) longLongForKey: (NSString*)key {
    return asLongLong(_get(_dict, key), _dict);
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return _getObject(_dict, key, [NSNumber class]);
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return _getObject(_dict, key, [NSString class]);
}


#pragma mark - Check Existence


- (BOOL) containsObjectForKey: (NSString*)key {
    return !_get(_dict, key).isEmpty();
}


#pragma mark - Convert to NSDictionary


- (NSDictionary<NSString*,id>*) toDictionary {
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: _dict.count()];
    for (MDict<id>::iterator i(_dict); i; ++i) {
        result[i.nativeKey()] = [i.nativeValue() cbl_toPlainObject];
    }
    return result;
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    return [self.keys countByEnumeratingWithState: state objects: buffer count: len];
}


#pragma mark - SUBSCRIPTING


- (CBLReadOnlyFragment*) objectForKeyedSubscript: (NSString*)key {
    if (![self containsObjectForKey: key])
        return nil;
    return [[CBLReadOnlyFragment alloc] initWithParent: self key: key];
}


#pragma mark - CBLConversion


- (id) cbl_toPlainObject {
    return [self toDictionary];
}


- (id) cbl_toCBLObject {
    return [self mutableCopy];
}


@end
