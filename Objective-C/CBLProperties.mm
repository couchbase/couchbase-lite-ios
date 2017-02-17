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
#import "CBLSharedKeys.hh"

@interface CBLProperties()

@property (nonatomic, readonly, nonnull) NSMapTable* sharedStrings;

@end

@implementation CBLProperties {
    cbl::SharedKeys _sharedKeys;
    FLDict _root;
    NSMutableDictionary* _properties;
    NSMutableSet* _changesKeys;
    BOOL _hasChanges;
}


@synthesize hasChanges=_hasChanges, sharedStrings = _sharedStrings;


- (instancetype) initWithSharedKeys:(cbl::SharedKeys)sharedKeys {
    self = [super init];
    if (self) {
        _sharedKeys = sharedKeys;
    }
    return self;
}


- (void) setSharedKeys: (cbl::SharedKeys*)sharedKeys {
    _sharedKeys = *sharedKeys;
}


- (cbl::SharedKeys*) sharedKeys {
    return &_sharedKeys;
}


- (nullable NSDictionary*) properties {
    if (!_properties && !self.hasChanges)
        _properties = [self.savedProperties mutableCopy];
    else if (_root && !self.hasChanges)
        [self loadRootIntoProperties];
    return _properties;
}


- (void) setProperties: (NSDictionary*)properties {
    if (properties == _properties)
        return;
    
    // Convert each property value if needed, build up changedKeys set, and invalidate
    // obsolete subdocuments:
    NSMutableSet* changesKeys = [NSMutableSet setWithCapacity: [properties count]];
    NSMutableDictionary* result = properties ? [properties mutableCopy] : nil;
    [properties enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        result[key] = [self convertValue: value oldValue: _properties[key] forKey: key];
        [changesKeys addObject: key];
    }];
    
    // Invalidate obsolete subdocuments from the current _properties:
    if ([_properties count] > 0) {
        NSSet* oldKeys = [NSSet setWithArray: [_properties allKeys]];
        NSSet* removedKeys = [NSSet my_differenceOfSet: oldKeys andSet: changesKeys];
        for (NSString* key in removedKeys) {
            [self invalidateIfSubdocument: _properties[key]];
        }
    }
    
    // Add keys from _root that do not exist in the changedKeys (deleting):
    if (_root) {
        FLDictIterator iter;
        FLDictIterator_Begin(_root, &iter);
        NSString *key;
        while (nullptr != (key = FLDictIterator_GetKey(&iter, &_sharedKeys))) {
            if (![changesKeys containsObject: key])
                [changesKeys addObject: key];
            FLDictIterator_Next(&iter);
        }
    }
    
    // Update _properties:
    _properties = result;
    
    // Mark changes:
    _changesKeys = changesKeys;
    self.hasChanges = YES;
}


- (void) revert {
    for (NSString* key in _changesKeys) {
        id value = _properties[key];
        if ([value isKindOfClass:[CBLSubdocument class]]) {
            CBLSubdocument* subdoc = $cast(CBLSubdocument, value);
            if ([subdoc hasRoot]) {
                [subdoc revert];
                continue; // Keep the subdocument value:
            }
            // Invalidate the subdocument set to the properties:
            [subdoc invalidate];
        } else if ([value isKindOfClass: [NSArray class]]) {
            for (id v in value) {
                CBLSubdocument* subdoc = $castIf(CBLSubdocument, v);
                if (subdoc)
                    [subdoc invalidate];
            }
        }
        _properties[key] = nil;
    }
    _changesKeys = nil;
    self.hasChanges = NO;
}


static inline NSNumber* numberProperty(NSDictionary* dict, NSString* key) {
    return $castIf(NSNumber, dict[key]);
}


- (BOOL) booleanForKey: (NSString*)key {
    id v = _properties[key];
    if (v || self.hasChanges) {
        if (!v || [v isKindOfClass: [NSNull class]])
            return NO;
        else {
            id n = $castIf(NSNumber, v);
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
    id v = numberProperty(_properties, key);
    return v || self.hasChanges ? [v doubleValue] : FLValue_AsDouble([self fleeceValueForKey: key]);
}


- (float) floatForKey: (NSString*)key {
    id v = numberProperty(_properties, key);
    return v || self.hasChanges ? [v floatValue] : FLValue_AsFloat([self fleeceValueForKey: key]);
}


- (NSInteger) integerForKey: (NSString*)key {
    id v = numberProperty(_properties, key);
    return v || self.hasChanges ? [v integerValue] : FLValue_AsInt([self fleeceValueForKey: key]);
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
    if (self.hasChanges)
        return _properties[key] != nil;
    else
        return [self fleeceValueForKey: key]  != nullptr;
}


#pragma mark - SUBSCRIPTION


- (nullable id) objectForKeyedSubscript: (NSString*)key {
    id obj = _properties[key];
    if (obj || self.hasChanges)
        return obj;
    
    obj = [self fleeceValueToObject: [self fleeceValueForKey: key] forKey: key];
    [self cacheValue: obj forKey: key changed: NO];
    return obj;
}


- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key {
    id oldValue = self[key];
    if (!$equal(value, oldValue)) {
        value = [self convertValue: value oldValue: oldValue forKey: key];
        [self mutateProperties];
        [self cacheValue: value forKey: key changed: YES];
        [self markChangedKey: key];
    }
}


#pragma mark - INTERNAL:


- (void) setRootDict: (nullable FLDict)root {
    _root = root;
    _sharedKeys.useDocumentRoot(_root);
}


// Update all subdocuments in _properties with the new FLDict values and invalidate all
// obsolete subdocuments. Other properties beside subdocuments and array will be removed so that
// they can be reread from the new root. This method is called after the new root has been updated
// to the document when saving the document or updating the document from external changes.
- (void) useNewRoot {
    if (!_properties)
        return;
    
    NSDictionary* nuProps = [_properties my_dictionaryByUpdatingValues: ^id(id key, id value) {
        FLValue fValue = [self fleeceValueForKey: key];
        return [self updateRootIfSubdocument: value withFleeceValue: fValue forKey: key];
    }];
    _properties = [nuProps mutableCopy];
}


- (id) updateRootIfSubdocument: (id)value withFleeceValue: (FLValue)fValue forKey: (NSString*)key {
    if ([value isKindOfClass: [CBLSubdocument class]]) {
        CBLSubdocument* subdoc = $cast(CBLSubdocument, value);
        FLDict dict = FLValue_AsDict(fValue);
        if (dict == nullptr) {
            [self invalidateIfSubdocument: subdoc];
            return nil;
        }
        
        subdoc.sharedKeys = self.sharedKeys;
        [subdoc setRootDict: dict];
        [subdoc useNewRoot];
        return subdoc;
    } else if ([value isKindOfClass: [NSArray class]]) {
        FLArray fArray = FLValue_AsArray(fValue);
        if (fArray == nullptr) {
            [self invalidateIfSubdocument: value];
            return nil;
        }
        
        NSArray* array = $cast(NSArray, value);
        NSMutableArray* result = [NSMutableArray arrayWithCapacity: FLArray_Count(fArray)];
        uint i = 0;
        FLArrayIterator iter;
        FLArrayIterator_Begin(fArray, &iter);
        FLValue item;
        while (nullptr != (item = FLArrayIterator_GetValue(&iter))) {
            id obj = i < [array count] ? array[i++] : nil;
            if (obj)
                obj = [self updateRootIfSubdocument: obj withFleeceValue: item forKey: key];
            obj = obj ?: [self fleeceValueToObject: item forKey: key];
            [result addObject: obj];
            FLArrayIterator_Next(&iter);
        }
        
        // Invalidate the rest of the subdocuments not including in the new array:
        for (; i < [array count]; i++) {
            [self invalidateIfSubdocument: array[i]];
        }
        return result;
    }
    return nil;
}


- (BOOL) hasRoot {
    return _root != nullptr;
}


- (nullable NSDictionary*) savedProperties {
    if (_properties && !self.hasChanges) {
        [self loadRootIntoProperties];
        return _properties;
    } else
        return [self fleeceRootToDictionary: _root];
}


- (BOOL) storeBlob: (CBLBlob*)blob error: (NSError**)error {
    AssertAbstractMethod();
}


- (CBLBlob*) blobWithProperties: (NSDictionary*)properties error: (NSError**)error {
    AssertAbstractMethod();
}


- (FLSliceResult) encodeWith: (FLEncoder)encoder error: (NSError**)outError {
    FLEncoder_BeginDict(encoder, [_properties count]);
    for (NSString *key in _properties) {
        CBLStringBytes bKey(key);
        FLEncoder_WriteKey(encoder, bKey);
        id value = _properties[key];
        if([value isKindOfClass:[CBLBlob class]] && ![self storeBlob:value error:outError])
            return (FLSliceResult){nullptr, 0};
        FLEncoder_WriteNSObject(encoder, value);
    }
    FLEncoder_EndDict(encoder);
    
    FLError flErr;
    auto body = FLEncoder_Finish(encoder, &flErr);
    if(!body.buf) {
        convertError(flErr, outError);
        return (FLSliceResult){nullptr, 0};
    }
    
    return body;
}


#pragma mark - PRIVATE:


- (void) mutateProperties {
    if (!_properties) {
        _properties = [[self fleeceRootToDictionary: _root] mutableCopy];
        if (!_properties)
            _properties = [NSMutableDictionary new];
    } else if (_root != nullptr && !self.hasChanges)
        [self loadRootIntoProperties];
}


- (void) loadRootIntoProperties {
    assert(!self.hasChanges);
    assert(_root != nullptr && _properties);
    
    if ([_properties count] == FLDict_Count(_root))
        return; // already loaded.
    
    FLDictIterator iter;
    FLDictIterator_Begin(_root, &iter);
    NSString *key;
    while (nullptr != (key = FLDictIterator_GetKey(&iter, &_sharedKeys))) {
        if (!_properties[key])
            _properties[key] = [self fleeceValueToObject: FLDictIterator_GetValue(&iter) forKey: key];
        FLDictIterator_Next(&iter);
    }
}


- (void) markChangedKey: (NSString*)key {
    if (![_changesKeys containsObject: key]) {
        if (!_changesKeys)
            _changesKeys = [NSMutableSet set];
        [_changesKeys addObject: key];
        
        if (!_hasChanges)
            self.hasChanges = YES;
    }
}


- (void) resetChangesKeys {
    [_properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self resetChangesKeysIfSubdocument: obj];
    }];
    
    _changesKeys = nil;
    self.hasChanges = NO;
}


- (void) resetChangesKeysIfSubdocument: (id)value {
    if ([value isKindOfClass: [CBLSubdocument class]]) {
        CBLSubdocument* subdoc = $cast(CBLSubdocument, value);
        [subdoc resetChangesKeys];
    } else if ([value isKindOfClass: [NSArray class]]) {
        NSArray* array = $cast(NSArray, value);
        for (id obj in array) {
            [self resetChangesKeysIfSubdocument: obj];
        }
    }
}


// Cache all value if changed = YES, but cache only subdocument or array if changed = NO.
- (void) cacheValue: (nullable id)value forKey: (NSString*)key changed: (BOOL)changed {
    if (changed ||
        [value isKindOfClass: [CBLSubdocument class]] ||
        [value isKindOfClass: [NSArray class]]) {
        if (!_properties)
            _properties = [NSMutableDictionary dictionary];
        [_properties setValue: value forKey: key];
    }
}


- (id) convertValue: (nullable id)value oldValue: (nullable id)oldValue forKey: (NSString*)key {
    if ($equal(value, oldValue))
        return value; // nothing to convert
    
    if ([value isKindOfClass: [NSDate class]])
        return [CBLJSON JSONObjectWithDate: value];
    else if ([value isKindOfClass: [CBLSubdocument class]])
        return [self convertSubdoc: value oldValue: oldValue forKey: key];
    else if ([value isKindOfClass: [NSDictionary class]])
        return [self convertDict: value oldValue: oldValue forKey: key];
    else if ([value isKindOfClass: [NSArray class]])
        return [self convertArray: value oldVale: oldValue forKey: key];
    else {
        [self invalidateIfSubdocument: oldValue];
        return value;
    }
}


- (id) convertSubdoc: (CBLSubdocument*)subdoc oldValue: (nullable id)oldValue forKey: (NSString*)key {
    // If the subdocument has already set to a property, copy its properties:
    id parent = subdoc.parent; // Make strong parent
    if (parent) {
        CBLSubdocument* oldSubdoc = $castIf(CBLSubdocument, oldValue);
        if (parent == self && $equal(subdoc.key, key)) { // e.g. array reorder case:
            if (oldSubdoc)
                [oldSubdoc invalidate];
            return subdoc;
        } else {
            // Copy the properties value into the old subdocument or copy the new subdoc:
            if (oldSubdoc) {
                oldSubdoc.properties = subdoc.properties;
                return oldSubdoc;
            } else
                subdoc = [subdoc copy];
        }
    }
    
    // Install subdocument:
    subdoc.parent = self;
    subdoc.key = key;
    [subdoc setOnMutate: [self onMutateBlockForKey: key]];
    
    // Invalidate the old absolete subdocument:
    [self invalidateIfSubdocument: oldValue];
    
    return subdoc;
}


- (id) convertDict: (NSDictionary*)dict oldValue: (nullable id)oldValue forKey: (NSString*)key {
    id obj = [self convertDictionary: dict];
    if (!obj) {
        CBLSubdocument* subdoc = $castIf(CBLSubdocument, oldValue);
        if (!subdoc)
            subdoc = [self createSubdocumentForKey: key];
        subdoc.properties = dict;
        return subdoc;
    }
    return obj;
}


- (id) convertArray: (NSArray*)array oldVale: (nullable id)oldValue forKey: (NSString*)key {
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: [array count]];
    NSArray* oldArray = $castIf(NSArray, oldValue);
    
    NSMutableSet* arraySet = nil;
    if ([oldArray count] > 0)
        arraySet = [NSMutableSet setWithArray: array];
    
    uint i;
    for (i = 0; i < [array count]; i++) {
        id nValue = array[i];
        id oValue = [oldArray count] > i ? oldArray[i] : nil;
        
        // FIXME: Array can be nested, using a simple arraySet is not enough 
        if ([oValue isKindOfClass: [CBLSubdocument class]] && [arraySet containsObject: oValue]) {
            // Prevent the subdocument to be invalidated so the subdocument can be reordered:
            oValue = nil;
        }
        
        nValue = [self convertValue: nValue oldValue: oValue forKey: key];
        [result addObject: nValue];
    }
    
    // Invalidate the rest of the old array values that are not included in the result:
    for (; i < [oldArray count]; i++) {
        [self invalidateIfSubdocument: oldArray[i]];
    }
    
    return result;
}


- (CBLSubdocument*) createSubdocumentForKey: (NSString*)key {
    cbl::SharedKeys sk(*self.sharedKeys);
    CBLSubdocument* subdoc = [[CBLSubdocument alloc] initWithParent: self sharedKeys: sk];
    subdoc.key = key;
    [subdoc setOnMutate: [self onMutateBlockForKey: key]];
    return subdoc;
}


- (CBLOnMutateBlock) onMutateBlockForKey: (NSString*)key {
    __weak typeof(self) weakSelf = self;
    return ^{
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf markChangedKey: key];
    };
}


// Invalidate Subdocument or Subdocuments in an array:
- (void) invalidateIfSubdocument: (id)value  {
    if ([value isKindOfClass: [CBLSubdocument class]])
        [value invalidate];
    else if ([value isKindOfClass: [NSArray class]]) {
        for (id v in value ) {
            [self invalidateIfSubdocument: v];
        }
    }
}


#pragma mark - PRIVATE: FLEECE


- (id) convertDictionary: (NSDictionary*)dict {
    NSString* type = dict[@"_cbltype"];
    if (type) {
        if ([type isEqualToString: @"blob"])
            return [self blobWithProperties: dict error: nil];
    }
    return nil; // Invalid!
}


- (FLSlice)typeForDict:(FLDict)dict {
    FLSlice typeKey = FLSTR("_cbltype");
    FLValue type = FLDict_GetSharedKey(dict, typeKey, &_sharedKeys);
    return FLValue_AsString(type);
}


- (FLValue) fleeceValueForKey: (NSString*) key {
    return FLDict_GetSharedKey(_root, CBLStringBytes(key), &_sharedKeys);
}


- (id) fleeceValueToObject: (FLValue)value forKey: (NSString*)key {
    switch (FLValue_GetType(value)) {
        case kFLArray: {
            FLArray array = FLValue_AsArray(value);
            FLArrayIterator iter;
            FLArrayIterator_Begin(array, &iter);
            auto result = [[NSMutableArray alloc] initWithCapacity: FLArray_Count(array)];
            FLValue item;
            while (nullptr != (item = FLArrayIterator_GetValue(&iter))) {
                [result addObject: [self fleeceValueToObject: item forKey: key]];
                FLArrayIterator_Next(&iter);
            }
            return result;
        }
        case kFLDict: {
            FLDict dict = FLValue_AsDict(value);
            FLSlice type = [self typeForDict:dict];
            if(!type.buf) {
                CBLSubdocument* subdoc = [self createSubdocumentForKey: key];
                [subdoc setRootDict: dict];
                return subdoc;
            }
            
            id result = FLValue_GetNSObject(value, &_sharedKeys);
            return [self convertDictionary: result];
        }
        default:
            return FLValue_GetNSObject(value, &_sharedKeys);
    }
}


- (NSDictionary*) fleeceRootToDictionary: (FLDict)root  {
    if (root == nullptr)
        return nil;
    
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity: FLDict_Count(root)];
    FLDictIterator iter;
    FLDictIterator_Begin(root, &iter);
    NSString *key;
    while (nullptr != (key = FLDictIterator_GetKey(&iter, &_sharedKeys))) {
        dict[key] = [self fleeceValueToObject: FLDictIterator_GetValue(&iter) forKey: key];
        FLDictIterator_Next(&iter);
    }
    return dict;
}


@end


#pragma mark - FLEECE ENCODING FOR CBLJSONEncoding:


@interface NSObject (CBLJSONEncoding)
@end

@implementation NSObject (CBLJSONEncoding)

- (void) fl_encodeTo:(FLEncoder)encoder {
    if([self conformsToProtocol:@protocol(CBLJSONCoding)]) {
        FLEncoder_WriteNSObject(encoder, [(id<CBLJSONCoding>)self jsonRepresentation]);
    } else {
        [NSException raise: NSInternalInconsistencyException
            format: @"Objects of class %@ cannot be stored as Couchbase Lite property values",
                     [self class]];
    }
}


@end
