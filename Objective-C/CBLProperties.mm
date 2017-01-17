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
    FLDict _root;             // For CBLDocument
    NSDictionary* _rootProps; // For CBLSubdocument
    
    NSMutableDictionary* _properties;
    BOOL _hasChanges;
}


@synthesize hasChanges=_hasChanges;


- (nullable NSDictionary*) properties {
    if (!_properties)
        _properties = [self.savedProperties mutableCopy];
    return _properties;
}


- (void) setProperties: (NSDictionary*)properties {
    _properties = properties ? [properties mutableCopy] : [NSMutableDictionary dictionary];
    [self markChanges];
}


static NSNumber* numberProperty(NSDictionary* dict, NSString* key) {
    id obj = dict[key];
    return [obj isKindOfClass: [NSNumber class]] ? obj : nil;
}


- (BOOL) booleanForKey: (NSString*)key {
    if (_properties || _rootProps)
        return [numberProperty(_properties ? _properties : _rootProps, key) boolValue];
    else
        return FLValue_AsBool([self fleeceValueForKey: key]);
    return NO;
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    NSString* dateStr = [self stringForKey: key];
    return [CBLJSON dateWithJSONObject: dateStr];
}


- (double) doubleForKey: (NSString*)key {
    if (_properties || _rootProps)
        return [numberProperty(_properties ? _properties : _rootProps, key) doubleValue];
    else
        return FLValue_AsDouble([self fleeceValueForKey: key]);
}


- (float) floatForKey: (NSString*)key {
    if (_properties || _rootProps)
        return [numberProperty(_properties ? _properties : _rootProps, key) floatValue];
    else
        return FLValue_AsFloat([self fleeceValueForKey: key]);
}


- (NSInteger) integerForKey: (NSString*)key {
    if (_properties || _rootProps)
        return [numberProperty(_properties ? _properties : _rootProps, key) integerValue];
    else
        return (NSInteger)FLValue_AsInt([self fleeceValueForKey: key]);
}


- (nullable id) objectForKey: (NSString*)key {
    return [self objectForKeyedSubscript: key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    if (_properties || _rootProps)
        return _properties ? _properties[key] : _rootProps[key];
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
    id retVal = nil;
    if (_properties)
        retVal = _properties[key];
    else
        retVal = [self fleeceValueToObject: [self fleeceValueForKey: key]];
    
    if([retVal isKindOfClass:[NSDictionary class]]) {
        NSDictionary* dict = retVal;
        NSString* blobHint = dict[@"_cbltype"];
        if(blobHint == nil) {
            return retVal;
        }
        
        if([blobHint isEqualToString:@"blob"]) {
            NSDictionary* props = dict[@"_properties"];
            retVal = [self readBlobWithProperties:props error:nil];
        }
        
        self[key] = retVal;
    }
    
    return retVal;
}


- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key {
    [self mutateProperties];
    
    // NSDate:
    if ([value isKindOfClass: NSDate.class])
        value = [CBLJSON JSONObjectWithDate: value];
    
    id oldValue = _properties[key];
    
    if (![value isEqual: oldValue] && value != oldValue) {
        [_properties setValue: value forKey: key];
        [self markChanges];
    }
}


#pragma mark - INTERNAL:


- (void) setRootDict: (nullable FLDict)root orProperties: (nullable NSDictionary*) props {
    _root = nullptr, _rootProps = nil;
    if (root != nullptr)
        _root = root;
    if (props)
        _rootProps = props;
    
    // Reset hasChanges flag:
    self.hasChanges = NO;
}


- (void) resetChanges {
    _properties = nil;
    _hasChanges = NO;
}


- (FLSharedKeys) sharedKeys {
    [NSException raise: NSInternalInconsistencyException
                format: @"Abstract method -sharedKeys was not overridden"];
    abort();
}

- (BOOL)translateAndStoreBlobs:(NSError * _Nullable __autoreleasing *)error {
    for (NSString* key in [self properties]) {
        id value = self[key];
        if([value isKindOfClass:[CBLBlob class]]) {
            CBLBlob *blob = value;
            if(![self storeBlob:blob error:error]) {
                return NO;
            }
            
            self[key] = @{@"_cbltype":@"blob",@"_properties":blob.properties};
        }
    }
    
    return YES;
}

- (BOOL)storeBlob:(CBLBlob *)blob error:(NSError * _Nullable __autoreleasing *)error {
    if(error != nil) {
        *error = [NSError errorWithDomain:@"LiteCore" code:kC4ErrorUnimplemented userInfo:
                 @{NSLocalizedDescriptionKey:@"CBLProperties does not know how to handle Blob datatype"}];
    }
    
    return NO;
}

- (CBLBlob *)readBlobWithProperties:(NSDictionary *)properties error:(NSError * _Nullable __autoreleasing *)error {
    if(error != nil) {
        *error = [NSError errorWithDomain:@"LiteCore" code:kC4ErrorUnimplemented userInfo:
                  @{NSLocalizedDescriptionKey:@"CBLProperties does not know how to handle Blob datatype"}];
    }
    
    return nil;
}


- (void) propertiesDidChange { }


#pragma mark - PRIVATE:


- (nullable NSDictionary*) savedProperties {
    if (_properties && !self.hasChanges)
        return _properties;
    if (_root)
        return [self fleeceValueToObject: (FLValue)_root];
    else
        return _rootProps;
}


- (void) mutateProperties {
    if (!_properties)
        _properties = [self.savedProperties mutableCopy];
    if (!_properties)
        _properties = [NSMutableDictionary dictionary];
}


- (void) markChanges {
    self.hasChanges = YES;
}


#pragma mark - PRIVATE: FLEECE


- (FLValue) fleeceValueForKey: (NSString*) key {
    return FLDict_GetSharedKey(_root, CBLStringBytes(key), [self sharedKeys]);
}


- (id) fleeceValueToObject: (FLValue)value {
    return FLValue_GetNSObject(value, [self sharedKeys], nil);
}


@end

// TODO:
// * Subdocument (In progress)
// * Support Blob
