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


- (cbl::SharedKeys*) sharedKeys {
    return &_sharedKeys;
}


- (nullable NSDictionary*) properties {
    if (!_properties)
        _properties = [self.savedProperties mutableCopy];
    return _properties;
}


- (void) setProperties: (NSDictionary*)properties {
    NSMutableDictionary* props = properties ? [properties mutableCopy] : [NSMutableDictionary dictionary];
    [properties enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        if([value isKindOfClass:[NSDictionary class]]) {
            id converted = [self convertDictionary:value];
            if (converted)
                props[key] = converted;
        }
    }];

    _properties = props;
    [self markChanges];
}


static inline NSNumber* numberProperty(NSDictionary* dict, NSString* key) {
    return $castIf(NSNumber, dict[key]);
}


- (BOOL) booleanForKey: (NSString*)key {
    if (_properties)
        return [numberProperty(_properties, key) boolValue];
    else
        return FLValue_AsBool([self fleeceValueForKey: key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [CBLJSON dateWithJSONObject: self[key]];
}


- (double) doubleForKey: (NSString*)key {
    if (_properties)
        return [numberProperty(_properties, key) doubleValue];
    else
        return FLValue_AsDouble([self fleeceValueForKey: key]);
}


- (float) floatForKey: (NSString*)key {
    if (_properties)
        return [numberProperty(_properties, key) floatValue];
    else
        return FLValue_AsFloat([self fleeceValueForKey: key]);
}


- (NSInteger) integerForKey: (NSString*)key {
    if (_properties)
        return [numberProperty(_properties, key) integerValue];
    else
        return (NSInteger)FLValue_AsInt([self fleeceValueForKey: key]);
}


- (nullable id) objectForKey: (NSString*)key {
    return [self objectForKeyedSubscript: key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    if (_properties)
        return $castIf(NSString, _properties[key]);
    else
        return slice2string((FLValue_AsString([self fleeceValueForKey: key])));
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
    if (_properties)
        return _properties[key];
    else
        return [self fleeceValueToObject: [self fleeceValueForKey: key]];
}


- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key {
    // NSDate:
    if ([value isKindOfClass: NSDate.class])
        value = [CBLJSON JSONObjectWithDate: value];

    if (_hasChanges || !$equal(value, self[key])) {
        [self mutateProperties];
        [_properties setValue: value forKey: key];
        [self markChanges];
    }
}


#pragma mark - INTERNAL:


- (void) setRootDict: (nullable FLDict)root {
    _root = root;
    _sharedKeys.useDocumentRoot(_root);
}


- (void) resetChanges {
    _properties = nil;
    self.hasChanges = NO;
}


- (BOOL)storeBlob:(CBLBlob *)blob error:(NSError **)error {
    AssertAbstractMethod();
}


- (CBLBlob *)blobWithProperties:(NSDictionary *)properties error:(NSError **)error {
    AssertAbstractMethod();
}


- (FLSliceResult)encodeWith:(FLEncoder)encoder error:(NSError **)outError {
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


- (void) propertiesDidChange { }


- (nullable NSDictionary*) savedProperties {
    if (_properties && !self.hasChanges)
        return _properties;
    else
        return [self fleeceRootToDictionary: _root];
}


#pragma mark - PRIVATE:


- (void) mutateProperties {
    if (!_properties) {
        _properties = [[self fleeceRootToDictionary: _root] mutableCopy];
        if (!_properties)
            _properties = [NSMutableDictionary new];
    }
}


- (void) markChanges {
    if (!_hasChanges)
        self.hasChanges = YES;
}


#pragma mark - PRIVATE: FLEECE

- (id)convertDictionary:(NSDictionary *)dict {
    NSString *type = dict[@"_cbltype"];
    if([type isEqualToString:@"blob"]) {
        return [self blobWithProperties:dict error:nil];
    }

    // Invalid!
    return nil;
}

- (FLSlice)typeForDict:(FLDict)dict {
    FLSlice typeKey = FLSTR("_cbltype");
    FLValue type = FLDict_GetSharedKey(dict, typeKey, &_sharedKeys);
    return FLValue_AsString(type);
}


- (FLValue) fleeceValueForKey: (NSString*) key {
    return FLDict_GetSharedKey(_root, CBLStringBytes(key), &_sharedKeys);
}


- (id) fleeceValueToObject: (FLValue)value {
    switch (FLValue_GetType(value)) {
        case kFLArray: {
            FLArray array = FLValue_AsArray(value);
            FLArrayIterator iter;
            FLArrayIterator_Begin(array, &iter);
            auto result = [[NSMutableArray alloc] initWithCapacity: FLArray_Count(array)];
            FLValue item;
            while (nullptr != (item = FLArrayIterator_GetValue(&iter))) {
                [result addObject: [self fleeceValueToObject: item]];
                FLArrayIterator_Next(&iter);
            }
            return result;
        }
        case kFLDict: {
            FLDict dict = FLValue_AsDict(value);
            FLSlice type = [self typeForDict:dict];
            if(!type.buf) {
                // TODO: convert to subdocument (using 'dict')
                return FLValue_GetNSObject(value, &_sharedKeys);
            }

            id result = FLValue_GetNSObject(value, &_sharedKeys);
            return [self convertDictionary:result];
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
        dict[key] = [self fleeceValueToObject: FLDictIterator_GetValue(&iter)];
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

// TODO:
// * Subdocument (In progress)
