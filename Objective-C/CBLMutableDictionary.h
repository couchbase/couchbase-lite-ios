//
//  CBLMutableDictionary.h
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

#import <Foundation/Foundation.h>
#import "CBLDictionary.h"
#import "CBLMutableDictionaryFragment.h"
@class CBLMutableArray;
@class CBLMutableDictionary;

NS_ASSUME_NONNULL_BEGIN

/** CBLMutableDictionary protocol defines a set of methods for writing dictionary data. */
@protocol CBLMutableDictionary <CBLDictionary, CBLMutableDictionaryFragment>

#pragma mark - Type Setters

/**
 Set a value for the given key. Allowed value types are CBLMutableArray, CBLBlob, CBLMutableDictionary,
 NSArray, NSDate, NSDictionary, NSNumber, NSNull, NSString. The NSArrays and NSDictionaries must
 contain only the above types. An NSDate value will be converted to an ISO-8601 format string.
 A nil value will be converted an NSNull.
 
 @param value The value.
 @param key The key.
 */
- (void) setValue: (nullable id)value forKey: (NSString*)key;

/**
 Set an String object for the given key. A nil value will be converted to an NSNull.
 
 @param value The String object.
 */
- (void) setString: (nullable NSString*)value forKey: (NSString*)key;

/**
 Set an NSNumber object for the given key. A nil value will be converted to an NSNull.
 
 @param value The NSNumber object.
 */
- (void) setNumber: (nullable NSNumber*)value forKey: (NSString*)key;

/**
 Set an integer value for the given key.
 
 @param value The integer value.
 */
- (void) setInteger: (NSInteger)value forKey: (NSString*)key;

/**
 Set a long long value for the given key.
 
 @param value The long long value.
 */
- (void) setLongLong: (long long)value forKey: (NSString*)key;

/**
 Set a float value for the given key.
 
 @param value The float value.
 */
- (void) setFloat: (float)value forKey: (NSString*)key;

/**
 Set a double value for the given key.
 
 @param value The double value.
 */
- (void) setDouble: (double)value forKey: (NSString*)key;

/**
 Set a boolean value for the given key.
 
 @param value The boolean value.
 */
- (void) setBoolean: (BOOL)value forKey: (NSString*)key;

/**
 Set a Date object for the given key. A nil value will be converted to an NSNull.
 
 @param value The Date object.
 */
- (void) setDate: (nullable NSDate*)value forKey: (NSString*)key;

/** 
 Set a CBLBlob object for the given key. A nil value will be converted to an NSNull.
 
 @param value The CBLBolb object.
 */
- (void) setBlob: (nullable CBLBlob*)value forKey: (NSString*)key;

/**
 Set a CBLArray object for the given key. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 */
- (void) setArray: (nullable CBLArray*)value forKey: (NSString*)key;

/** 
 Set a CBLDictionary object for the given key. A nil value will be converted to an NSNull.
 
 @param value The CBLDictionary object.
 */
- (void) setDictionary: (nullable CBLDictionary*)value forKey: (NSString*)key;

#pragma mark - Removing Entries

/** 
 Removes a given key and its value from the dictionary.
 
 @param key The key.
 */
- (void) removeValueForKey: (NSString*)key;

#pragma mark - Data

/**
 Set data for the dictionary. Allowed value types are CBLArray, CBLBlob,
 CBLDictionary, NSArray, NSDate, NSDictionary, NSNumber, NSNull, and NSString.
 The NSArrays and NSDictionaries must contain only the above types.
 
 @param data The data.
 */
- (void) setData: (nullable NSDictionary<NSString*,id>*)data;

#pragma mark - Getting dictionary and array object

/** 
 Get a property's value as a CBLMutableArray, which is a mapping object of an array value.
 Returns nil if the property doesn't exists, or its value is not an array.
 
 @param key The key.
 @return The CBLMutableArray object or nil if the property doesn't exist.
 */
- (nullable CBLMutableArray*) arrayForKey: (NSString*)key;

/** 
 Get a property's value as a CBLMutableDictionary, which is a mapping object of a dictionary
 value. Returns nil if the property doesn't exists, or its value is not a dictionary.
 
 @param key The key.
 @return The CBLMutableDictionary object or nil if the key doesn't exist.
 */
- (nullable CBLMutableDictionary*) dictionaryForKey: (NSString*)key;

#pragma mark - Subscript

/** 
 Subscripting access to a CBLMutableFragment object that represents the value of the dictionary by key.
 
 @param key The key.
 @return The CBLMutableFragment object.
 */
- (nullable CBLMutableFragment*) objectForKeyedSubscript: (NSString*)key;

@end

/** CBLMutableDictionary is a mutable version of the CBLDictionary. */
@interface CBLMutableDictionary : CBLDictionary <CBLMutableDictionary>

#pragma mark - Initializers

/** Creates a new empty CBLMutableDictionary object. */
+ (instancetype) dictionary;

/** Initialize a new empty CBLMutableDictionary object. */
- (instancetype) init;

/** 
 Initialzes a new CBLMutableDictionary object with data. Allowed value types are
 CBLArray, CBLBlob, CBLDictionary, NSArray, NSDate, NSDictionary, NSNumber,
 NSNull, and NSString. The NSArrays and NSDictionaries must contain only the
 above types.
 
 @param data The data.
 */
- (instancetype) initWithData: (nullable NSDictionary<NSString*,id>*)data;

@end

NS_ASSUME_NONNULL_END
