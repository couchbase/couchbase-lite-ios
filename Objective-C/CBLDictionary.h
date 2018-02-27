//
//  CBLDictionary.h
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
#import "CBLDictionaryFragment.h"
@class CBLBlob;
@class CBLArray;
@class CBLDictionary;
@class CBLMutableDictionary;


NS_ASSUME_NONNULL_BEGIN

/** CBLDictionary protocol defines a set of methods for reading dictionary data. */
@protocol CBLDictionary <NSObject, CBLDictionaryFragment, NSFastEnumeration>

#pragma mark - Counting Entries

/** The number of entries in the dictionary. */
@property (readonly, nonatomic) NSUInteger count;

#pragma mark - Accessing Keys

/** An array containing all keys, or an empty array if the dictionary has no entries. */
@property (readonly, copy, nonatomic) NSArray<NSString*>* keys;

#pragma mark - Type Setters

/**
 Gets a property's value. The object types are CBLBlob, CBLArray,
 CBLDictionary, NSNumber, or NSString based on the underlying data type; or nil if the
 property value is NSNull or the property doesn't exist.
 
 @param key The key.
 @return The object value or nil.
 */
- (nullable id) valueForKey: (NSString*)key;

/**
 Gets a property's value as a string.
 Returns nil if the property doesn't exist, or its value is not a string.
 
 @param key The key.
 @return The NSString object or nil.
 */
- (nullable NSString*) stringForKey: (NSString*)key;

/**
 Gets a property's value as a number.
 Returns nil if the property doesn't exist, or its value is not a number.
 
 @param key The key.
 @return The NSNumber object or nil.
 */
- (nullable NSNumber*) numberForKey: (NSString*)key;

/**
 Gets a property's value as an integer value.
 Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
 Returns 0 if the property doesn't exist or does not have a numeric value.
 
 @param key The key.
 @return The integer value.
 */
- (NSInteger) integerForKey: (NSString*)key;

/**
 Gets a property's value as a long long value.
 Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
 Returns 0 if the property doesn't exist or does not have a numeric value.
 
 @param key The key.
 @return The long long value.
 */
- (long long) longLongForKey: (NSString*)key;

/**
 Gets a property's value as a float value.
 Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
 Returns 0.0 if the property doesn't exist or does not have a numeric value.
 
 @param key The key.
 @return The float value.
 */
- (float) floatForKey: (NSString*)key;

/**
 Gets a property's value as a double value.
 Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
 Returns 0.0 if the property doesn't exist or does not have a numeric value.
 
 @param key The key.
 @return The double value.
 */
- (double) doubleForKey: (NSString*)key;

/**
 Gets a property's value as a boolean.
 Returns YES if the value exists, and is either `true` or a nonzero number.
 
 @param key The key.
 @return The boolean value.
 */
- (BOOL) booleanForKey: (NSString*)key;

/** 
 Gets a property's value as an NSDate.
 JSON does not directly support dates, so the actual property value must be a string, which is
 then parsed according to the ISO-8601 date format (the default used in JSON.)
 Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
 NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
 without milliseconds.
 
 @param key The key.
 @return The NSDate object or nil.
 */
- (nullable NSDate*) dateForKey: (NSString*)key;

/**
 Get a property's value as a CBLBlob.
 Returns nil if the property doesn't exist, or its value is not a CBLBlob.
 
 @param key The key.
 @return The CBLBlob object or nil.
 */
- (nullable CBLBlob*) blobForKey: (NSString*)key;

/**
 Get a property's value as a CBLArray, which is a mapping object of an array value.
 Returns nil if the property doesn't exists, or its value is not an array.
 
 @param key The key.
 @return The CBLArray object or nil.
 */
- (nullable CBLArray*) arrayForKey: (NSString*)key;

/** 
 Get a property's value as a CBLDictionary, which is a mapping object of
 a dictionary value.
 Returns nil if the property doesn't exists, or its value is not a dictionary.
 
 @param key The key.
 @return The CBLDictionary object or nil.
 */
- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key;


#pragma mark - Check existence

/** 
 Tests whether a property exists or not.
 This can be less expensive than -valuetForKey:, because it does not have to allocate an
 NSObject for the property value.
 
 @param key The key.
 @return The boolean value representing whether a property exists or not.
 */
- (BOOL) containsValueForKey: (NSString*)key;

#pragma mark - Data

/**
 Gets content of the current object as an NSDictionary. The value types of the
 values contained in the returned NSArray object are CBLBlob, NSArray,
 NSDictionary, NSNumber, NSNull, and NSString.
 
 @return The NSDictionary object representing the content of the current object.
 */
- (NSDictionary<NSString*,id>*) toDictionary;

@end

/** CBLDictionary provides read access to dictionary data. */
@interface CBLDictionary : NSObject <CBLDictionary, NSCopying, NSMutableCopying>

- (instancetype) init NS_UNAVAILABLE;

- (CBLMutableDictionary*) toMutable;

@end

NS_ASSUME_NONNULL_END
