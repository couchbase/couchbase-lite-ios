//
//  CBLMutableArray.h
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
#import "CBLArray.h"
#import "CBLMutableArrayFragment.h"
@class CBLMutableDictionary;
@class CBLMutableArray;

NS_ASSUME_NONNULL_BEGIN

/** CBLMutableArray protocol defines a set of methods for getting and setting array data. */
@protocol CBLMutableArray <CBLArray, CBLMutableArrayFragment>

#pragma mark - Type Setters

/**
 Sets a value at the given index. A nil value will be converted to an NSNull.
 
 @param value The value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setValue: (nullable id)value atIndex: (NSUInteger)index;

/**
 Sets an String object at the given index. A nil value will be converted to an NSNull.
 
 @param value The String object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setString: (nullable NSString*)value atIndex: (NSUInteger)index;

/**
 Sets an NSNumber object at the given index. A nil value will be converted to an NSNull.
 
 @param value The NSNumber object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index;

/**
 Sets an integer value at the given index.
 
 @param value The integer value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setInteger: (NSInteger)value atIndex: (NSUInteger)index;

/**
 Sets a long long value at the given index.
 
 @param value The long long value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setLongLong: (long long)value atIndex: (NSUInteger)index;

/**
 Sets a float value at the given index.
 
 @param value The float value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setFloat: (float)value atIndex: (NSUInteger)index;

/**
 Sets a double value at the given index.
 
 @param value The double value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setDouble: (double)value atIndex: (NSUInteger)index;

/** 
 Sets a boolean value at the given index.
 
 @param value The boolean value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setBoolean: (BOOL)value atIndex: (NSUInteger)index;

/** 
 Sets a Date object at the given index. A nil value will be converted to an NSNull.
 
 @param value The Date object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setDate: (nullable NSDate*)value atIndex: (NSUInteger)index;

/**
 Sets a CBLBlob object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLBlob object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index;

/**
 Sets a CBLArray object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setArray: (nullable CBLArray*)value atIndex: (NSUInteger)index;

/**
 Sets a CBLDictionary object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLDictionary object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index;

#pragma mark - Type Appenders

/**
 Adds a value to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The value.
 */
- (void) addValue: (nullable id)value;

/**
 Adds a String object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The String object.
 */
- (void) addString: (nullable NSString*)value;

/**
 Adds an NSNumber object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The NSNumber object.
 */
- (void) addNumber: (nullable NSNumber*)value;

/**
 Adds an integer value to the end of the array.
 
 @param value The integer value.
 */
- (void) addInteger: (NSInteger)value;

/**
 Adds a long long value to the end of the array.
 
 @param value The long long value.
 */
- (void) addLongLong: (long long)value;

/**
 Adds a float value to the end of the array.
 
 @param value The float value.
 */
- (void) addFloat: (float)value;

/**
 Adds a double value to the end of the array.
 
 @param value The double value.
 */
- (void) addDouble: (double)value;

/**
 Adds a boolean value to the end of the array.
 
 @param value The boolean value.
 */
- (void) addBoolean: (BOOL)value;

/**
 Adds a Date object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The Date object.
 */
- (void) addDate: (nullable NSDate*)value;

/** 
 Adds a CBLBlob object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The CBLMutableArray object.
 */
- (void) addBlob: (nullable CBLBlob*)value;

/**
 Adds a CBLArray object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 */
- (void) addArray: (nullable CBLArray*)value;

/** 
 Adds a CBLDictionary object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The CBLDictionary object.
 */
- (void) addDictionary: (nullable CBLDictionary*)value;

#pragma mark - Type Inserters

/**
 Inserts a value at the given index. A nil value will be converted to an NSNull.
 an NSNull object.
 
 @param value  The value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertValue: (nullable id)value atIndex: (NSUInteger)index;

/**
 Inserts an String object at the given index. A nil value will be converted to an NSNull.
 
 @param value The String object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertString: (nullable NSString*)value atIndex: (NSUInteger)index;

/**
 Inserts an NSNumber object at the given index. A nil value will be converted to an NSNull.
 
 @param value The NSNumber object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index;

/**
 Inserts an integer value at the given index.
 
 @param value The integer value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertInteger: (NSInteger)value atIndex: (NSUInteger)index;

/**
 Inserts a long long value at the given index.
 
 @param value The long long value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertLongLong: (long long)value atIndex: (NSUInteger)index;

/**
 Inserts a float value at the given index.
 
 @param value The float value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertFloat: (float)value atIndex: (NSUInteger)index;

/**
 Inserts a double value at the given index.
 
 @param value The double value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertDouble: (double)value atIndex: (NSUInteger)index;

/**
 Inserts a boolean value at the given index.
 
 @param value The boolean value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertBoolean: (BOOL)value atIndex: (NSUInteger)index;

/**
 Inserts a Date object at the given index. A nil value will be converted to an NSNull.
 
 @param value The Date object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertDate: (nullable NSDate*)value atIndex: (NSUInteger)index;

/** 
 Inserts a CBLBlob object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLBlob object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index;

/** 
 Inserts a CBLDictionary object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLDictionary object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index;

/**
 Inserts a CBLArray object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertArray: (nullable CBLArray*)value atIndex: (NSUInteger)index;

#pragma mark - Removing Value

/** 
 Removes the object at the given index.
 
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) removeValueAtIndex: (NSUInteger)index;

#pragma mark - Getting CBLMutableArray and CBLMutableDictionary

/** 
 Gets a CBLMutableArray at the given index. Returns nil if the value is not an array.
 
 @param index The index. This value must not exceed the bounds of the array.
 @return The CBLMutableArray object.
 */
- (nullable CBLMutableArray*) arrayAtIndex: (NSUInteger)index;

/** 
 Gets a CBLMutableDictionary at the given index. Returns nil if the value is not a dictionary.
 
 @param index The index. This value must not exceed the bounds of the array.
 @return The CBLMutableDictionary object.
 */
- (nullable CBLMutableDictionary*) dictionaryAtIndex: (NSUInteger)index;

#pragma mark - Data

/**
 Set data for the array. Allowed value types are CBLArray, CBLBlob,
 CBLDictionary, NSArray, NSDate, NSDictionary, NSNumber, NSNull, and
 NSString. The NSArrays and NSDictionaries must contain only the above types.
 
 @param data The data.
 */
- (void) setData: (nullable NSArray*)data;

#pragma mark - Subscript

/** 
 Subscripting access to a CBLMutableFragment object that represents the value at the given index.
 
 @param index The index. If the index value exceeds the bounds of the array,
               the CBLMutableFragment will represent a nil value.
 @return The CBLMutableFragment object.
 */
- (nullable CBLMutableFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end

/** CBLMutableArray provides access to array data. */
@interface CBLMutableArray : CBLArray <CBLMutableArray>

#pragma mark - Initializers

/** Creates a new empty CBLMutableArray object. */
+ (instancetype) array;

/** Initialize a new empty CBLMutableArray object. */
- (instancetype) init;

/** 
 Initialize a new CBLMutableArray object with data. Allowed value types are
 CBLArray, CBLBlob, CBLDictionary, NSArray, NSDate, NSDictionary,
 NSNumber, NSNull, and NSString. The NSArrays and NSDictionaries must contain
 only the above types.
 
 @param data The data.
 */
- (instancetype) initWithData: (nullable NSArray*)data;

@end

NS_ASSUME_NONNULL_END
