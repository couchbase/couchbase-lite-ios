//
//  CBLReadOnlyArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArrayFragment.h"
@class CBLBlob;
@class CBLReadOnlyDictionary;
@class CBLReadOnlyArray;

NS_ASSUME_NONNULL_BEGIN

/** CBLReadOnlyArray protocol defines a set of methods for readonly accessing array data. */
@protocol CBLReadOnlyArray <NSObject, CBLReadOnlyArrayFragment, NSFastEnumeration>

/** Gets a number of the items in the array. */
@property (readonly) NSUInteger count;

/** Gets value at the given index as an object. The object types are CBLBlob,
    CBLReadOnlyArray, CBLReadOnlyDictionary, NSNumber, or NSString based on the underlying
    data type; or nil if the value is nil.
    @param index    the index.
    @result the object or nil. */
- (nullable id) objectAtIndex: (NSUInteger)index;

/** Gets value at the given index as a boolean. 
    Returns YES if the value exists, and is either `true` or a nonzero number.
    @param index    the index.
    @result the boolean value. */
- (BOOL) booleanAtIndex: (NSUInteger)index;

/** Gets value at the given index as an integer.
    Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    Returns 0 if the value doesn't exist or does not have a numeric value.
    @param index    the index.
    @result the integer value. */
- (NSInteger) integerAtIndex: (NSUInteger)index;

/** Gets value at the given index as a float.
    Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    Returns 0.0 if the value doesn't exist or does not have a numeric value.
    @param index    the index.
    @result the float value. */
- (float) floatAtIndex: (NSUInteger)index;

/** Gets value at the given index as a double.
    Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    Returns 0.0 if the property doesn't exist or does not have a numeric value.
    @param index    the index.
    @result the double value. */
- (double) doubleAtIndex: (NSUInteger)index;

/** Gets value at the given index as a string.
    Returns nil if the value doesn't exist, or its value is not a string.
    @param index    the index.
    @result the NSString object or nil. */
- (nullable NSString*) stringAtIndex: (NSUInteger)index;

/** Gets value at the given index as a number.
    Returns nil if the value doesn't exist, or its value is not a number.
    @param index    the index.
    @result the NSNumber object or nil. */
- (nullable NSNumber*) numberAtIndex: (NSUInteger)index;

/** Gets value at the given index as an NSDate.
    JSON does not directly support dates, so the actual property value must be a string, which is
    then parsed according to the ISO-8601 date format (the default used in JSON.)
    Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
    NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    without milliseconds.
    @param index    the index.
    @result the NSDate object or nil. */
- (nullable NSDate*) dateAtIndex: (NSUInteger)index;

/** Get value at the given index as a CBLBlob.
    Returns nil if the value doesn't exist, or its value is not a CBLBlob.
    @param index    the index.
    @result the CBLBlob object or nil. */
- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index;

/** Get value at the given index as a CBLReadOnlyDictionary, which is a mapping object of 
    a dictionary value.
    Returns nil if the value doesn't exists, or its value is not a dictionary.
    @param index    the index.
    @result the CBLReadOnlyDictionary object or nil. */
- (nullable CBLReadOnlyDictionary*) dictionaryAtIndex: (NSUInteger)index;

/** Gets value as a CBLReadOnlyArray, which is a mapping object of an array value.
    Returns nil if the value doesn't exists, or its value is not an array.
    @param index    the index.
    @result the CBLReadOnlyArray object or nil. */
- (nullable CBLReadOnlyArray*) arrayAtIndex: (NSUInteger)index;

/** Gets content of the current object as an NSArray. The values contained in the returned
    NSArray object are all JSON based values.
    @result the NSArray object representing the content of the current object in the JSON format. */
- (NSArray*) toArray;

@end

/** CBLReadOnlyArray provides readonly access to array data. */
@interface CBLReadOnlyArray : NSObject <CBLReadOnlyArray>

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
