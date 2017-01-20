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


- (void) setProperties: (NSDictionary*)properties {
    _properties = [self convertProperties: properties];
    
    _changedNames = nil;
    [self markChangedKeys: [_properties allKeys]];
}


static NSNumber* numberProperty(id value) {
    return [value isKindOfClass: [NSNumber class]] ? value : nil;
}


- (BOOL) booleanForKey: (NSString*)key {
    id v = _properties ? _properties[key] : nil;
    return v ? [numberProperty(v) boolValue] : FLValue_AsBool([self fleeceValueForKey: key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    NSString* dateStr = [self stringForKey: key];
    return dateStr ? [CBLJSON dateWithJSONObject: dateStr] : nil;
}


- (double) doubleForKey: (NSString*)key {
    id v = _properties ? _properties[key] : nil;
    return v ? [numberProperty(v) doubleValue] : FLValue_AsDouble([self fleeceValueForKey: key]);
}


- (float) floatForKey: (NSString*)key {
    id v = _properties ? _properties[key] : nil;
    return v ? [numberProperty(v) floatValue] : FLValue_AsFloat([self fleeceValueForKey: key]);
}


- (NSInteger) integerForKey: (NSString*)key {
    id v = _properties ? _properties[key] : nil;
    return v ? [numberProperty(v) integerValue] : FLValue_AsInt([self fleeceValueForKey: key]);
}


- (nullable id) objectForKey: (NSString*)key {
    return self[key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    id v = _properties ? _properties[key] : nil;
    return v ? $castIf(NSString, v) : slice2string((FLValue_AsString([self fleeceValueForKey: key])));
}


- (CBLSubdocument*) subdocumentForKey: (NSString*)key {
    id subdoc = self[key];
    if (!subdoc) {
        subdoc = [self subdocumentWithRoot: nullptr withProperties: nil forKey: key];
        [self cacheValue: subdoc forKey: key changed: NO];
    }
    return subdoc;
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
    id obj = _properties ? _properties[key] : nil;
    if (!obj) {
        auto value = [self fleeceValueForKey: key];
        obj = [self fleeceValueToObject: value  forKey: key asJson: NO];
        [self cacheValue: obj forKey: key changed: NO];
    }
    return obj;
}


- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key {
    // NSDate:
    if ([value isKindOfClass: NSDate.class])
        value = [CBLJSON JSONObjectWithDate: value];
    
    id oldValue = _properties[key];
    
    if (![value isEqual: oldValue] && value != oldValue) {
        value = [self convertValue: value oldValue: oldValue forKey: key];
        [self cacheValue: value forKey: key changed: YES];
        [self markChanges];
    }
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


- (void) revertChanges {
    for (NSString* key in _changedNames) {
        id value = _properties[key];
        if ([value isKindOfClass: [CBLSubdocument class]]) {
            CBLSubdocument* subdoc = $cast(CBLSubdocument, value);
            [subdoc revertChanges];
            if (!subdoc.root) {
                [subdoc invalidate];
                _properties[key] = nil;
            }
        } else {
            if ([value isKindOfClass: [NSArray class]]) {
                for (id obj in value) {
                    CBLSubdocument* subdoc = $castIf(CBLSubdocument, obj);
                    [subdoc invalidate];
                }
            }
            _properties[key] = nil;
        }
        
    }
    _changedNames = nil;
    _hasChanges = NO;
}


- (FLSharedKeys) sharedKeys {
    [NSException raise: NSInternalInconsistencyException
                format: @"Abstract method -sharedKeys was not overridden"];
    abort();
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
        if (_properties[key] != nil && ![_changedNames containsObject: key])
            [_changedNames addObject: key];
    }
    [self markChanges];
}


/** Convert properties content into Subdocuments where dictionaries are found.*/
- (NSMutableDictionary*) convertProperties: (NSDictionary*)properties {
    NSMutableDictionary* result = [properties mutableCopy];
    for (NSString* key in properties) {
        id oldValue = _properties ? _properties[key] : nil;
        id nuValue = properties[key];
        result[key] = [self convertValue: nuValue oldValue: oldValue forKey: key];
    }
    return result;
}


- (id) convertValue: (id)value oldValue: (nullable id)oldValue forKey: (NSString*)key {
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
        NSArray* oldArray = $castIf(NSArray, oldValue);
        NSArray* nuArray = (NSArray*)value;
        NSMutableArray* result = [NSMutableArray arrayWithCapacity: nuArray.count];
        for (int i = 0; i < nuArray.count; i++) {
            id oldValue = oldArray && i < oldArray.count ? oldArray[i] : nil;
            id nuValue = nuArray[i];
            result[i] = [self convertValue: nuValue oldValue: oldValue forKey: key];
        }
        
        // Invalidate:
        if (oldArray && oldArray.count > nuArray.count) {
            for (int i = (int)nuArray.count; i < oldArray.count; i++) {
                CBLSubdocument* oldSubdoc = $castIf(CBLSubdocument, oldArray[i]);
                [oldSubdoc invalidate];
            }
        } else {
            CBLSubdocument* oldSubdoc = $castIf(CBLSubdocument, oldValue);
            [oldSubdoc invalidate];
        }
        return result;
    } else {
        CBLSubdocument* nuSubdoc = $castIf(CBLSubdocument, value);
        [self attachSubdocument: nuSubdoc forKey: key];
        
        if ([oldValue isKindOfClass: [CBLSubdocument class]])
            [oldValue invalidate];
    }
    return value;
}


- (NSDictionary*) currentPropertiesAsJson: (BOOL)asJson {
    NSMutableDictionary* result;
    NSMutableSet *changedNames = [_changedNames mutableCopy];
    if (_root) {
        int count = FLDict_Count(_root);
        result = [NSMutableDictionary dictionaryWithCapacity: count];
        if (count > 0) {
            FLDictIterator iter;
            FLDictIterator_Begin(_root, &iter);
            do {
                NSString* key = [self fleeceValueToKeyString: FLDictIterator_GetKey(&iter)];
                id value = _properties[key];
                if (value) {
                    if (asJson)
                        value = [self jsonValueForValue: value];
                    [changedNames removeObject: key];
                } else {
                    value = [self fleeceValueToObject: FLDictIterator_GetValue(&iter)
                                               forKey: key asJson: asJson];
                    [self cacheValue: value forKey: key changed: NO];
                }
                result[key] = value;
            } while (FLDictIterator_Next(&iter));
        }
        return result;
    }
    if (changedNames.count > 0) {
        if (!result)
            result = [NSMutableDictionary dictionaryWithCapacity: changedNames.count];
        for (NSString* key in _changedNames) {
            id value = _properties[key];
            result[key] = asJson ? [self jsonValueForValue: value] : value;
        }
    }
    return result;
}


- (id) jsonValueForValue: (id)value {
    if ([value conformsToProtocol: @protocol(CBLJSONEncoding)]) {
        return [(id<CBLJSONEncoding>)value encodeAsJSON];
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
    } else if ([value isKindOfClass: [NSArray class]]) {
        NSArray* array = $cast(NSArray, value);
        NSMutableArray* result = [NSMutableArray arrayWithCapacity: array.count];
        for (id obj in array) {
            id extObj = [self jsonValueForValue: obj];
            if (extObj)
                [result addObject: extObj];
        } return result;
    } else {
        return value;
    }
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
    
    NSDictionary* props = _properties;
    _properties = [NSMutableDictionary dictionary];
    
    // Update root to all subdocuments:
    for (NSString* key in props) {
        id value = props[key];
        if ([value isKindOfClass: [CBLSubdocument class]]) {
            CBLSubdocument* subdoc = (CBLSubdocument*)value;
            FLValue nuValue = _root ? [self fleeceValueForKey: key] : nullptr;
            if (FLValue_GetType(nuValue) == kFLDict) {
                subdoc.root = (FLDict)nuValue;
                _properties[key] = subdoc;
            } else
                [subdoc invalidate];
        } else if ([value isKindOfClass: [NSArray class]]) {
            NSArray* oldArray = (NSArray*)value;
            NSMutableArray* nuArray = nil;
            FLValue nuValue = _root ? [self fleeceValueForKey: key] : nullptr;
            if (FLValue_GetType(nuValue) == kFLArray)
                nuArray = [[self fleeceValueToObject: nuValue
                                              forKey: key asJson: NO] mutableCopy];
            BOOL completed = YES;
            if (nuArray) {
                for (int i = 0; i < nuArray.count; i++) {
                    id oldValue = oldArray && i < oldArray.count ? oldArray[i] : nil;
                    id nuValue = nuArray[i];
                    CBLSubdocument* oldSubdoc = $castIf(CBLSubdocument, oldValue);
                    CBLSubdocument* nuSubdoc = $castIf(CBLSubdocument, nuValue);
                    if (oldSubdoc && nuSubdoc) { // Update only both are subdocs, otherwise cancel.
                        oldSubdoc.root = nuSubdoc.root;
                        nuArray[i] = oldSubdoc;
                    } else {
                        completed = NO;
                        break;
                    }
                }
            }
            
            if (completed)
                _properties[key] = nuArray;
            else {
                for (id oldValue in oldArray) {
                    CBLSubdocument* oldSubdoc = $castIf(CBLSubdocument, oldValue);
                    [oldSubdoc invalidate];
                }
            }
        }
    }
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
    Assert(!subdoc.parent || subdoc.parent == self,
           @"Subdocument has already been set to a document or a subdocument.");
    if (!subdoc.parent)
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
            case kFLArray: {
                FLArray array = FLValue_AsArray(value);
                int count = FLArray_Count(array);
                NSMutableArray* result = [[NSMutableArray alloc] initWithCapacity: count];
                if (count > 0) {
                    FLArrayIterator iter;
                    FLArrayIterator_Begin(array, &iter);
                    do {
                        auto value = FLArrayIterator_GetValue(&iter);
                        id obj = [self fleeceValueToObject: value forKey: key asJson: asJson];
                        [result addObject: obj];
                    } while (FLArrayIterator_Next(&iter));
                }
                return result;
            }
            default:
                return FLValue_GetNSObject(value, self.sharedKeys, nil);
        }
    } else
        return FLValue_GetNSObject(value, self.sharedKeys, nil);
}


- (NSString*) fleeceValueToKeyString: (FLValue)value {
    NSString* key = nil;
    if (FLValue_IsInteger(value)) {
        auto encKey = FLValue_AsInt(value);
        auto k = FLSharedKey_GetKeyString(self.sharedKeys, (int)encKey, nil);
        key = slice2string(k);
    }
    if (!key)
        key = slice2string(FLValue_AsString(value));
    return key;
}


@end

// TODO:
// * Support Blob.
