//
//  CBLDictionary.mm
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

#import "CBLDictionary.h"
#import "CBLCoreBridge.h"
#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDictionary+Swift.h"
#import "CBLDocument+Internal.h"
#import "CBLFleece.hh"
#import "CBLJSON.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"
#import "MDict.hh"
#import "MDictIterator.hh"

using namespace cbl;
using namespace fleece;


@implementation CBLDictionary
{
    NSArray* _keys;
    __weak NSObject* _sharedLock;
}


@synthesize swiftObject=_swiftObject;


- (instancetype) initEmpty {
    self = [super init];
    if (self) {
        [self setupSharedLock];
    }
    return self;
}


- (instancetype) initWithMValue: (fleece::MValue<id>*)mv
                       inParent: (fleece::MCollection<id>*)parent
{
    self = [super init];
    if (self) {
        _dict.initInSlot(mv, parent);
        [self setupSharedLock];
    }
    return self;
}


- (instancetype) initWithCopyOfMDict: (const MDict<id>&)mDict
                           isMutable: (bool)isMutable
{
    self = [super init];
    if (self) {
        _dict.initAsCopyOf(mDict, isMutable);
        [self setupSharedLock];
    }
    return self;
}


- (void) setupSharedLock {
    id db;
    if (_dict.context() != MContext::gNullContext)
        db = ((DocContext*)_dict.context())->database();
    _sharedLock = db != nil ? db : self;
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


- (CBLMutableDictionary*) mutableCopyWithZone:(NSZone *)zone {
    CBL_LOCK(_sharedLock) {
        return [[CBLMutableDictionary alloc] initWithCopyOfMDict: _dict isMutable: true];
    }
}


- (MCollection<id>*) fl_collection {
    return &_dict;
}


#pragma mark - Counting Entries


- (NSUInteger) count {
    CBL_LOCK(_sharedLock) {
        return _dict.count();
    }
}


#pragma mark - Accessing Keys


- (NSArray*) keys {
    // I cache the keys array because my -countByEnumeratingWithState method delegates to it,
    // but it's not actually retained by anything related to the enumeration, so it's otherwise
    // possible for the array to be dealloced while the enumeration is going on.
    CBL_LOCK(_sharedLock) {
        if (!_keys) {
            NSMutableArray* keys = [NSMutableArray arrayWithCapacity: _dict.count()];
            for (MDict<id>::iterator i(_dict); i; ++i)
                [keys addObject: i.nativeKey()];
            _keys = keys;
        }
        return _keys;
    }
}


- (void) keysChanged {
    // My subclass CBLMutableDictionary calls this when it's mutated, to invalidate the array
    CBL_LOCK(_sharedLock) {
        _keys = nil;
    }
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


- (nullable id) valueForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return _getObject(_dict, key, nil);
    }
}


- (nullable NSString*) stringForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return _getObject(_dict, key, [NSString class]);
    }
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return _getObject(_dict, key, [NSNumber class]);
    }
}


- (NSInteger) integerForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return asInteger(_get(_dict, key), _dict);
    }
}


- (long long) longLongForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return asLongLong(_get(_dict, key), _dict);
    }
}


- (float) floatForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return asFloat(_get(_dict, key), _dict);
    }
}


- (double) doubleForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return asDouble(_get(_dict, key), _dict);
    }
}


- (BOOL) booleanForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return asBool(_get(_dict, key), _dict);
    }
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return asDate(_getObject(_dict, key, nil));
    }
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return _getObject(_dict, key, [CBLBlob class]);
    }
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return _getObject(_dict, key, [CBLArray class]);
    }
}


- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return _getObject(_dict, key, [CBLDictionary class]);
    }
}


#pragma mark - Check Existence


- (BOOL) containsValueForKey: (NSString*)key {
    CBL_LOCK(_sharedLock) {
        return !_get(_dict, key).isEmpty();
    }
}


#pragma mark - Data


- (NSDictionary<NSString*,id>*) toDictionary {
    CBL_LOCK(_sharedLock) {
        NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: _dict.count()];
        for (MDict<id>::iterator i(_dict); i; ++i) {
            result[i.nativeKey()] = [i.nativeValue() cbl_toPlainObject];
        }
        return result;
    }
}


#pragma mark - Mutable


- (CBLMutableDictionary*) toMutable {
    return [self mutableCopy];
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    return [self.keys countByEnumeratingWithState: state objects: buffer count: len];
}


#pragma mark - Subscript


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    if (![self containsValueForKey: key])
        return nil;
    return [[CBLFragment alloc] initWithParent: self key: key];
}


#pragma mark - Equality


- (BOOL) isEqual: (id)object {
    if (self == object)
        return YES;
    
    id <CBLDictionary> other = $castIfProtocol(CBLDictionary, object);
    if (!other)
        return NO;
    
    if (self.count != other.count)
        return NO;
    
    for (NSString* key in self) {
        NSString* value = [self valueForKey: key];
        if (value) {
            if (![value isEqual: [other valueForKey: key]])
                return NO;
        } else {
            if ([other valueForKey: key] || ![other containsValueForKey: key])
                return NO;
        }
    }
    return YES;
}


- (NSUInteger) hash {
    CBL_LOCK(self.sharedLock) {
        NSUInteger hash = 0;
        for (MDict<id>::iterator i(_dict); i; ++i) {
            hash += ([i.nativeKey() hash] ^ [i.nativeValue() hash]);
        }
        return hash;
    }
}


#pragma mark - Lock

- (NSObject*) sharedLock {
    return _sharedLock;
}


#pragma mark - CBLConversion


- (id) cbl_toPlainObject {
    return [self toDictionary];
}


- (id) cbl_toCBLObject {
    return [self mutableCopy];
}


#pragma mark Fleece


- (void) fl_encodeToFLEncoder: (FLEncoder)enc {
    CBL_LOCK(_sharedLock) {
        SharedEncoder encoder(enc);
        _dict.encodeTo(encoder);
    }
}


#pragma mark - FLEncodable


// Encode independently of the document. CBLBlob objects will not be installed
// in the database and will be encoded with their content directly.
- (FLSliceResult) encode: (NSError**)outError {
    CBL_LOCK(_sharedLock) {
        FLEncoder enc;
        if (_dict.context() != MContext::gNullContext) {
            CBLDatabase* db = ((DocContext*)_dict.context())->database();
            enc = c4db_getSharedFleeceEncoder(db.c4db);
        } else
            enc = FLEncoder_New();
        
        FLError err;
        [self fl_encodeToFLEncoder: enc];
        FLSliceResult body = FLEncoder_Finish(enc, &err);
        
        if (_dict.context() != MContext::gNullContext)
            FLEncoder_Free(enc);
        
        if (!body.buf)
            convertError(err, outError);
        return body;
    }
}


@end
