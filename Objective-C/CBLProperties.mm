//
//  CBLProperties.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#import "CBLProperties.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLJSON.h"
#import "CBLInternal.h"


@implementation CBLProperties {
    FLDict _root;
    NSMutableDictionary* _properties;
    NSMutableSet* _changedNames;
    BOOL _hasChanges;
}

@synthesize root=_root, hasChanges=_hasChanges;


#pragma mark - PROPERTY ACCESSORS


- (nullable NSDictionary*) properties {
    return [self currentPropertiesAsJson: NO];
}


- (void) setProperties: (nullable NSDictionary*)properties {
    _properties = [self convertProperties: properties];
    _changedNames = nil;
    
    __block NSMutableArray* changedKeys = [NSMutableArray array];
    if (properties)
        [changedKeys addObjectsFromArray: [properties allKeys]];
    
    if (FLDict_Count(_root) > 0) {
        NSSet* keys = [NSSet setWithArray: changedKeys];
        [self iterateFleeceDict: _root withBlock: ^(NSString *key, FLValue value) {
            if (![keys containsObject: keys])
                [changedKeys addObject: key];
        }];
    }
    [self markChangedKeys: changedKeys];
}


static NSNumber* numberProperty(id value) {
    return [value isKindOfClass: [NSNumber class]] ? value : nil;
}


- (BOOL) booleanForKey: (NSString*)key {
    id v = _properties[key];
    if (v) {
        if ([v isKindOfClass: [NSNull class]])
            return NO;
        else {
            id n = numberProperty(v);
            return n ? [n boolValue] : YES;
        }
    } else
        return FLValue_AsBool([self fleeceValueForKey: key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    NSString* dateStr = [self stringForKey: key];
    return [CBLJSON dateWithJSONObject: dateStr];
}


- (double) doubleForKey: (NSString*)key {
    id v = _properties[key];
    return v ? [numberProperty(v) doubleValue] : FLValue_AsDouble([self fleeceValueForKey: key]);
}


- (float) floatForKey: (NSString*)key {
    id v = _properties[key];
    return v ? [numberProperty(v) floatValue] : FLValue_AsFloat([self fleeceValueForKey: key]);
}


- (NSInteger) integerForKey: (NSString*)key {
    id v = _properties[key];
    return v ? [numberProperty(v) integerValue] : FLValue_AsInt([self fleeceValueForKey: key]);
}


- (nullable id) objectForKey: (NSString*)key {
    return self[key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return $castIf(NSString, self[key]);
}


- (nullable CBLSubdocument*) subdocumentForKey: (NSString*)key {
    return $castIf(CBLSubdocument, self[key]);
}


- (void) setBoolean: (BOOL)value forKey: (NSString*)key {
    self[key] = @(value);
}


- (void) setDouble: (double)value forKey: (NSString*)key {
    self[key] = @(value);
}


- (void) setFloat: (float)value forKey: (NSString*)key {
    self[key] = @(value);
}


- (void) setInteger: (NSInteger)value forKey: (NSString*)key {
    self[key] = @(value);
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    self[key] = value;
}


- (void) removeObjectForKey: (NSString*)key {
    self[key] = nil;
}


- (BOOL) containsObjectForKey: (NSString*)key {
    if (_properties)
        return _properties[key] != nil;
    else
        return [self fleeceValueForKey: key]  != nullptr;
}


#pragma mark - SUBSCRIPTION


- (nullable id) objectForKeyedSubscript: (NSString*)key {
    id obj = _properties[key];
    if (!obj && ![_changedNames containsObject: key]) {
        auto value = [self fleeceValueForKey: key];
        if (value == nullptr)
            return nil;
        obj = [self fleeceValueToObject: value  forKey: key asJson: NO];
        [self cacheValue: obj forKey: key changed: NO];
    }
    return obj;
}


- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key {
    id oldValue = self[key];
    if (![value isEqual: oldValue] && value != oldValue) {
        value = [self convertValue: value oldValue: oldValue forKey: key];
        [self cacheValue: value forKey: key changed: YES];
        [self markChanges];
    }
}


- (void) revert {
    for (NSString* key in _changedNames) {
        id value = _properties[key];
        CBLSubdocument* subdoc = $castIf(CBLSubdocument, value);
        if (subdoc) {
            [subdoc revert];
            if (!subdoc.root) {
                [subdoc invalidate];
                _properties[key] = nil;
            }
        } else
            _properties[key] = nil;
    }
    
    _changedNames = nil;
    self.hasChanges = NO;
}


- (FLSharedKeys) sharedKeys {
    [NSException raise: NSInternalInconsistencyException
                format: @"Abstract method -sharedKeys was not overridden"];
    abort();
}


#pragma mark - INTERNAL


- (void) setRoot: (FLDict)root {
    _root = root;
    
    // Update cache:
    [self updateCache];
    
    // Reset changed name:
    _changedNames = nil;
    
    // Reset hasChanges flag:
    self.hasChanges = NO;
}


#pragma mark - INTERNAL: CBLJSONEncoding


- (id) encodeAsJSON {
    return [self currentPropertiesAsJson: YES];
}


#pragma mark - PRIVATE:

- (void) markChanges {
    self.hasChanges = YES;
}


- (void) markChangedKey: (NSString*)key {
    [self markChangedKeys: @[key]];
}


- (void) markChangedKeys: (NSArray*)keys {
    if (!_changedNames)
        _changedNames = [NSMutableSet set];
    
    for (NSString* key in keys) {
        if (_properties[key] != nil)
            [_changedNames addObject: key];
    }
    [self markChanges];
}


/** Convert properties content into Subdocuments where dictionaries are found.*/
- (NSMutableDictionary*) convertProperties: (nullable NSDictionary*)properties {
    NSMutableDictionary* result = [properties mutableCopy];
    for (NSString* key in properties) {
        id oldValue = _properties ? _properties[key] : nil;
        id nuValue = properties[key];
        result[key] = [self convertValue: nuValue oldValue: oldValue forKey: key];
    }
    return result;
}


- (id) convertValue: (id)value oldValue: (nullable id)oldValue forKey: (NSString*)key {
    if (value && ![self validateValue: value inArray: NO]) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"Found unsupported value type on key: %@", key];
    }
    
    if ([value isKindOfClass: [NSDictionary class]]) {
        CBLSubdocument* subdoc = nil;
        // If the old value is a subdocument, use the old value:
        if ([oldValue isKindOfClass: [CBLSubdocument class]]) {
            subdoc = (CBLSubdocument*)oldValue;
            subdoc.properties = value;
        } else
            subdoc = [self subdocumentWithRoot: nullptr withProperties: value forKey: key];
        return subdoc;
    } else if ([value isKindOfClass: [NSArray class]]) {
        for (id obj in value) {
            // Now support only JSON object type in the array:
            if (![self validateValue: obj inArray: YES])
                [NSException raise: NSInternalInconsistencyException
                            format: @"Found unsupported value type in an array on key: %@", key];
        }
        return value;
    } else if ([value isKindOfClass: [NSDate class]]) {
        return [CBLJSON JSONObjectWithDate: value];
    } else {
        CBLSubdocument* nuSubdoc = $castIf(CBLSubdocument, value);
        if (nuSubdoc)
            [self attachSubdocument: nuSubdoc forKey: key];
        if (oldValue != nuSubdoc && [oldValue isKindOfClass: [CBLSubdocument class]])
            [oldValue invalidate];
    }
    return value;
}


- (BOOL) validateValue: (id)value inArray: (BOOL) inArray {
    return (([value isKindOfClass: [NSNumber class]] ||
             [value isKindOfClass: [NSString class]] ||
             [value isKindOfClass: [NSDictionary class]] ||
             [value isKindOfClass: [NSArray class]]) ||
            ([value isKindOfClass: [NSNull class]]) ||
            ([value isKindOfClass: [NSDate class]] && !inArray) ||
            ([value isKindOfClass: [CBLSubdocument class]] && !inArray));
}


- (NSDictionary*) currentPropertiesAsJson: (BOOL)asJson {
    NSMutableDictionary* result = [_properties mutableCopy];
    if (asJson) {
        for (NSString* key in _properties) {
            result[key] = [self jsonValueForValue: _properties[key]];
        }
    }
    
    if (_root) {
        if (!result)
            result = [NSMutableDictionary dictionaryWithCapacity: FLDict_Count(_root)];
        [self iterateFleeceDict: _root withBlock: ^(NSString *key, FLValue value) {
            if (![_changedNames containsObject: key] && !_properties[key]) {
                id obj = [self fleeceValueToObject: value forKey: key asJson: asJson];
                if (obj) {
                    [self cacheValue: obj forKey: key changed: NO];
                    result[key] = obj;
                }
            }
        }];
    }
    return result;
}


- (id) jsonValueForValue: (id)value {
    if ([value conformsToProtocol: @protocol(CBLJSONEncoding)]) {
        return [(id<CBLJSONEncoding>)value encodeAsJSON];
    } else if ([value isKindOfClass: [NSDate class]]) {
        return [CBLJSON JSONObjectWithDate: value];
    } else if ([value isKindOfClass: [NSDictionary class]]) {
        NSDictionary* dict = $cast(NSDictionary, value);
        NSMutableDictionary* result = [dict mutableCopy];
        for (NSString* key in dict) {
            id obj = dict[key];
            id extObj = [self jsonValueForValue: obj];
            if (obj != extObj)
                result[key] = extObj;
        }
        return result;
    } else
        return value;
}


#pragma mark - PRIVATE: CACHE


- (void) cacheValue: (nullable id)value forKey: (NSString*)key changed: (BOOL)changed {
    BOOL shouldCache = changed ||
                       [value isKindOfClass: [CBLSubdocument class]] ||
                       [value isKindOfClass: [NSArray class]];
    if (shouldCache) {
        if (!_properties)
            _properties = [NSMutableDictionary dictionary];
        _properties[key] = value;
    }
    
    if (changed) {
        if (!_changedNames)
            _changedNames = [[NSMutableSet alloc] init];
        [_changedNames addObject: key];
    }
}


/** Remove all changes and update subdocuments with a new root. */
- (void) updateCache {
    if (!_properties)
        return;
    
    NSDictionary* properties = _properties;
    _properties = [NSMutableDictionary dictionary];
    
    // Update root to all subdocuments:
    for (NSString* key in properties) {
        id value = properties[key];
        if ([value isKindOfClass: [CBLSubdocument class]]) {
            CBLSubdocument* subdoc = (CBLSubdocument*)value;
            FLValue nuValue = _root ? [self fleeceValueForKey: key] : nullptr;
            if (FLValue_GetType(nuValue) == kFLDict) {
                subdoc.root = (FLDict)nuValue;
                _properties[key] = subdoc;
            } else
                [subdoc invalidate];
        }
    }
    
    if (_properties.count == 0)
        _properties = nil;
}


#pragma mark - PRIVATE: SUBDOCUMENT


- (CBLSubdocument*) subdocumentWithRoot: (nullable FLDict)dict
                         withProperties: (nullable NSDictionary*)props
                                 forKey: (NSString*)key {
    CBLSubdocument* subdoc = [[CBLSubdocument alloc] initWithParent: self root: dict];
    [self attachSubdocument: subdoc forKey: key];
    if (props)
        subdoc.properties = props;
    return subdoc;
}


- (void) attachSubdocument: (CBLSubdocument*)subdoc forKey: (NSString*)key {
    id parent = subdoc.parent;
    Assert(!parent || parent == self,
           @"Subdocument has already been set to a document or a subdocument.");
    if (!parent)
        subdoc.parent = self;
    [subdoc setOnMutate: [self onMutateBlockForKey: key]];
}


- (CBLOnMutateBlock) onMutateBlockForKey: (NSString*)key {
    __weak typeof(self) weakSelf = self;
    return ^{
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf markChangedKey: key];
    };
}


#pragma mark - PRIVATE: FLEECE


- (FLValue) fleeceValueForKey: (NSString*) key {
    return FLDict_GetSharedKey(_root, CBLStringBytes(key), self.sharedKeys);
}


- (NSDictionary*) fleeceRootToProperties: (FLDict)root asJson: (BOOL)asJson {
    int count = FLDict_Count(root);
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: count];
    if (count > 0) {
        FLDictIterator iter;
        FLDictIterator_Begin(root, &iter);
        do {
            NSString* key = [self fleeceValueToKeyString: FLDictIterator_GetKey(&iter)];
            result[key] = [self fleeceValueToObject: FLDictIterator_GetValue(&iter)
                                             forKey: key
                                             asJson: asJson];
        } while (FLDictIterator_Next(&iter));
    }
    return result;
}


- (id) fleeceValueToObject: (FLValue)value forKey: (NSString*)key asJson: (BOOL)asJson {
    if (!asJson) {
        FLValueType type = FLValue_GetType(value);
        switch (type) {
            case kFLDict: {
                // TODO: Support Blob
                return [self subdocumentWithRoot: (FLDict)value withProperties: nil forKey:key];
            }
            default:
                return FLValue_GetNSObject(value, self.sharedKeys, nil);
        }
    } else
        return FLValue_GetNSObject(value, self.sharedKeys, nil);
}


- (NSString*) fleeceValueToKeyString: (FLValue)value {
    NSString* key = nil;
    if (FLValue_IsInteger(value))
        key = slice2string(FLSharedKey_GetKeyString(self.sharedKeys, (int)FLValue_AsInt(value), nil));
    if (!key)
        key = slice2string(FLValue_AsString(value));
    return key;
}


- (void) iterateFleeceDict: (FLDict)dict withBlock: (void(^)(NSString* key, FLValue value))block {
    if (FLDict_Count(dict) > 0) {
        FLDictIterator iter;
        FLDictIterator_Begin(_root, &iter);
        do {
            NSString* k = [self fleeceValueToKeyString: FLDictIterator_GetKey(&iter)];
            FLValue v = FLDictIterator_GetValue(&iter);
            block(k, v);
        } while (FLDictIterator_Next(&iter));
    }
}


@end

// TODO:
// * Support Blob.
