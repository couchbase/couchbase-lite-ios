//
//  CBLArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLArrayFragment.h"
@class CBLBlob;
@class CBLDictionary;
@class CBLArray;
@class CBLMutableArray;


NS_ASSUME_NONNULL_BEGIN

/** CBLArray protocol defines a set of methods for reading array data. */
@protocol CBLArray <NSObject, CBLArrayFragment, NSFastEnumeration>

/** Gets a number of the items in the array. */
@property (readonly) NSUInteger count;

/**
 Gets value at the given index as an object. The object types are CBLBlob,
 CBLArray, CBLDictionary, NSNumber, or NSString based on the underlying
 data type; or nil if the value is nil.
 
 @param index The index.
 @return The object or nil.
 */
- (nullable id) objectAtIndex: (NSUInteger)index;

/*
 Gets value at the given index. The object types are CBLBlob,
 CBLArray, CBLDictionary, NSNumber, or NSString based on the underlying
 data type; or nil if the value is nil.
 
 @param index The index.
 @return The object or nil.
 */
- (nullable id) valueAtIndex: (NSUInteger)index;

/**
 Gets value at the given index as a string.
 Returns nil if the value doesn't exist, or its value is not a string.
 
 @param index The index.
 @return The NSString object or nil.
 */
- (nullable NSString*) stringAtIndex: (NSUInteger)index;

/**
 Gets value at the given index as a number.
 Returns nil if the value doesn't exist, or its value is not a number.
 
 @param index The index.
 @return The NSNumber object or nil.
 */
- (nullable NSNumber*) numberAtIndex: (NSUInteger)index;

/**
 Gets value at the given index as an integer value.
 Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
 Returns 0 if the value doesn't exist or does not have a numeric value.
 
 @param index The index.
 @return The integer value.
 */
- (NSInteger) integerAtIndex: (NSUInteger)index;

/**
 Gets value at the given index as a long long value.
 Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
 Returns 0 if the value doesn't exist or does not have a numeric value.
 
 @param index The index.
 @return The long long value.
 */
- (long long) longLongAtIndex: (NSUInteger)index;

/**
 Gets value at the given index as a float value.
 Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
 Returns 0.0 if the value doesn't exist or does not have a numeric value.
 
 @param index The index.
 @return The float value.
 */
- (float) floatAtIndex: (NSUInteger)index;

/**
 Gets value at the given index as a double value.
 Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
 Returns 0.0 if the property doesn't exist or does not have a numeric value.
 
 @param index The index.
 @return The double value.
 */
- (double) doubleAtIndex: (NSUInteger)index;

/** 
 Gets value at the given index as a boolean.
 Returns YES if the value exists, and is either `true` or a nonzero number.
 
 @param index The index.
 @return The boolean value.
 */
- (BOOL) booleanAtIndex: (NSUInteger)index;

/**
 Gets value at the given index as an NSDate.
 JSON does not directly support dates, so the actual property value must be a string, which is
 then parsed according to the ISO-8601 date format (the default used in JSON.)
 Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
 NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
 without milliseconds.
 
 @param index The index.
 @return The NSDate object or nil.
 */
- (nullable NSDate*) dateAtIndex: (NSUInteger)index;

/**
 Get value at the given index as a CBLBlob.
 Returns nil if the value doesn't exist, or its value is not a CBLBlob.
 
 @param index The index.
 @return The CBLBlob object or nil.
 */
- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index;

/**
 Gets value as a CBLArray, which is a mapping object of an array value.
 Returns nil if the value doesn't exists, or its value is not an array.
 
 @param index The index.
 @return The CBLArray object or nil.
 */
- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index;

/**
 Get value at the given index as a CBLDictionary, which is a mapping object of
 a dictionary value.
 Returns nil if the value doesn't exists, or its value is not a dictionary.
 
 @param index The index.
 @return The CBLDictionary object or nil.
 */
- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index;

#pragma mark - Data

/**
 Gets content of the current object as an NSArray. The values contained in the returned
 NSArray object are all JSON based values.
 
 @return The NSArray object representing the content of the current object in the JSON format.
 */
- (NSArray*) toArray;

@end

/** CBLArray provides read access to array data. */
@interface CBLArray : NSObject <CBLArray>

- (instancetype) init NS_UNAVAILABLE;

- (CBLMutableArray*) toMutable;

@end

NS_ASSUME_NONNULL_END
