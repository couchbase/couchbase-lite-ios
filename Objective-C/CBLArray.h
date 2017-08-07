//
//  CBLArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArray.h"
#import "CBLArrayFragment.h"
@class CBLDictionary;
@class CBLArray;

NS_ASSUME_NONNULL_BEGIN

/** CBLArray protocol defines a set of methods for getting and setting array data. */
@protocol CBLArray <CBLReadOnlyArray, CBLArrayFragment>

#pragma mark - Type Setters


/** 
 Sets a CBLArray object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setArray: (nullable CBLArray*)value atIndex: (NSUInteger)index;

/** 
 Sets a CBLBlob object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLBlob object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index;

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
 Sets a CBLDictionary object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLDictionary object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index;

/** 
 Sets a double value at the given index.
 
 @param value The double value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setDouble: (double)value atIndex: (NSUInteger)index;

/** 
 Sets a float value at the given index.
 
 @param value The float value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setFloat: (float)value atIndex: (NSUInteger)index;

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
 Sets an NSNumber object at the given index. A nil value will be converted to an NSNull.
 
 @param value The NSNumber object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index;

/** 
 Sets an object at the given index. A nil value will be converted to an NSNull.
 
 @param value The object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setObject: (nullable id)value atIndex: (NSUInteger)index;

/** 
 Sets an String object at the given index. A nil value will be converted to an NSNull.
 
 @param value The String object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) setString: (nullable NSString*)value atIndex: (NSUInteger)index;

#pragma mark - Type Appenders

/** 
 Adds a CBLArray object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 */
- (void) addArray: (nullable CBLArray*)value;

/** 
 Adds a CBLBlob object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 */
- (void) addBlob: (nullable CBLBlob*)value;

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
 Adds a CBLDictionary object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The CBLDictionary object.
 */
- (void) addDictionary: (nullable CBLDictionary*)value;

/** 
 Adds a double value to the end of the array.
 
 @param value The double value.
 */
- (void) addDouble: (double)value;

/** 
 Adds a float value to the end of the array.
 
 @param value The float value.
 */
- (void) addFloat: (float)value;

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
 Adds an NSNumber object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The NSNumber object.
 */
- (void) addNumber: (nullable NSNumber*)value;

/** 
 Adds an object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The object.
 */
- (void) addObject: (nullable id)value;

/** 
 Adds a String object to the end of the array. A nil value will be converted to an NSNull.
 
 @param value The String object.
 */
- (void) addString: (nullable NSString*)value;


#pragma mark - Type Inserters


/** 
 Inserts a CBLArray object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertArray: (nullable CBLArray*)value atIndex: (NSUInteger)index;

/** 
 Inserts a CBLBlob object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLBlob object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index;

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
 Inserts a CBLDictionary object at the given index. A nil value will be converted to an NSNull.
 
 @param value The CBLDictionary object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index;

/** 
 Inserts a double value at the given index.
 
 @param value The double value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertDouble: (double)value atIndex: (NSUInteger)index;

/** 
 Inserts a float value at the given index.
 
 @param value The float value.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertFloat: (float)value atIndex: (NSUInteger)index;

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
 Inserts an NSNumber object at the given index. A nil value will be converted to an NSNull.
 
 @param value The NSNumber object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index;

/** 
 Inserts an object at the given index. A nil value will be converted to an NSNull.
 an NSNull object.
 
 @param object  The object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertObject: (nullable id)object atIndex: (NSUInteger)index;

/** 
 Inserts an String object at the given index. A nil value will be converted to an NSNull.
 
 @param value The String object.
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) insertString: (nullable NSString*)value atIndex: (NSUInteger)index;

#pragma mark - Setting content with an NSArray

/** 
 Set an array as a content. Allowed value types are NSArray, NSDate, NSDictionary, NSNumber,
 NSNull, NSString, CBLArray, CBLBlob, CBLDictionary. The NSArrays and NSDictionaries must
 contain only the above types. Setting the new array content will replace the current data
 including the existing CBLArray and CBLDictionary objects.
 
 @param array The array.
 */
- (void) setArray: (nullable NSArray*)array;

#pragma mark - Removing Value

/** 
 Removes the object at the given index.
 
 @param index The index. This value must not exceed the bounds of the array.
 */
- (void) removeObjectAtIndex: (NSUInteger)index;

#pragma mark - Getting CBLArray and CBLDictionary

/** 
 Gets a CBLArray at the given index. Returns nil if the value is not an array.
 
 @param index The index. This value must not exceed the bounds of the array.
 @return The CBLArray object.
 */
- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index;

/** 
 Gets a CBLDictionary at the given index. Returns nil if the value is not a dictionary.
 
 @param index The index. This value must not exceed the bounds of the array.
 @return The CBLDictionary object.
 */
- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index;

#pragma mark - Subscript

/** 
 Subscripting access to a CBLFragment object that represents the value at the given index.
 
 @param index The index. If the index value exceeds the bounds of the array,
               the CBLFragment will represent a nil value.
 @return The CBLFragment object.
 */
- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end

/** CBLArray provides access to array data. */
@interface CBLArray : CBLReadOnlyArray <CBLArray>

#pragma mark - Initializers

/** Creates a new empty CBLArray object. */
+ (instancetype) array;

/** Initialize a new empty CBLArray object. */
- (instancetype) init;

/** 
 Initialize a new CBLArray object with an array content. Allowed value types are NSArray,
 NSDate, NSDictionary, NSNumber, NSNull, NSString, CBLArray, CBLBlob, CBLDictionary.
 The NSArrays and NSDictionaries must contain only the above types.
 
 @param array The array object.
 */
- (instancetype) initWithArray: (NSArray*)array;

@end

NS_ASSUME_NONNULL_END
