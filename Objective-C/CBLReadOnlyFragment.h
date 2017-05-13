//
//  CBLReadOnlyFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArrayFragment.h"
#import "CBLReadOnlyDictionaryFragment.h"
@class CBLBlob;
@class CBLReadOnlyArray;
@class CBLReadOnlyDictionary;
@class CBLReadOnlyFragment;

NS_ASSUME_NONNULL_BEGIN

/** CBLReadOnlyFragment protocol provides readonly access to the data value wrapped by
    a fragment object. */
@protocol CBLReadOnlyFragment <NSObject>

/** Gets the value as an integer.
    Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    Returns 0 if the value is nil or is not a numeric value. */
@property (nonatomic, readonly) NSInteger integerValue;

/** Gets the value as a float.
    Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    Returns 0.0 if the value is nil or is not a numeric value. */
@property (nonatomic, readonly) float floatValue;

/** Gets the value as a double. 
    Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    Returns 0.0 if the value is nil or is not a numeric value. */
@property (nonatomic, readonly) double doubleValue;

/** Gets the value as a boolean.
    Returns YES if the value is not nil nor NSNull, and is either `true` or a nonzero number. */
@property (nonatomic, readonly) BOOL booleanValue;

/** Gets the value as an object. 
    The object types are CBLBlob, CBLReadOnlyArray, CBLReadOnlyDictionary, NSNumber, or NSString 
    based on the underlying data type; or nil if the value is nil. */
@property (nonatomic, readonly, nullable) NSObject* object;

/** Gets the value as a string. 
    Returns nil if the value is nil, or the value is not a string. */
@property (nonatomic, readonly, nullable) NSString* string;

/** Gets the value as a number. 
    Returns nil if the value is nil, or the value is not a number.*/
@property (nonatomic, readonly, nullable) NSNumber* number;

/** Gets the value as an NSDate.
    JSON does not directly support dates, so the actual property value must be a string, which is
    then parsed according to the ISO-8601 date format (the default used in JSON.)
    Returns nil if the value is nil, is not a string, or is not parseable as a date.
    NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    without milliseconds. */
@property (nonatomic, readonly, nullable) NSDate* date;

/** Get the value as a CBLBlob.
    Returns nil if the value is nil, or the value is not a CBLBlob. */
@property (nonatomic, readonly, nullable) CBLBlob* blob;

/** Get the value as a CBLReadOnlyArray, a mapping object of an array value.
    Returns nil if the value is nil, or the value is not an array. */
@property (nonatomic, readonly, nullable) CBLReadOnlyArray* array;

/** Get a property's value as a CBLReadOnlyDictionary, a mapping object of a dictionary value.
    Returns nil if the value is nil, or the value is not a dictionary. */
@property (nonatomic, readonly, nullable) CBLReadOnlyDictionary* dictionary;

/** Same as getting the value as an object. */
@property (nonatomic, readonly, nullable) NSObject* value;

/** Checks whether the value held by the fragment object exists or is nil value or not. */
@property (nonatomic, readonly) BOOL exists;

@end

/** CBLReadOnlyFragment provides readonly access to data value. CBLReadOnlyFragment also provides
    subscript access by either key or index to the nested values which are wrapped by the
    CBLReadOnlyFragment objects. */
@interface CBLReadOnlyFragment : NSObject <CBLReadOnlyFragment, CBLReadOnlyDictionaryFragment,
                                           CBLReadOnlyArrayFragment>

@end

NS_ASSUME_NONNULL_END
