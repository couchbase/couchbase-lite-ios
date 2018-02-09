//
//  CBLFragment.h
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
#import "CBLArrayFragment.h"
#import "CBLDictionaryFragment.h"
@class CBLBlob;
@class CBLArray;
@class CBLDictionary;
@class CBLFragment;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLFragment protocol provides read access to the data value wrapped by
 a fragment object.
 */
@protocol CBLFragment <NSObject>

/**
 Gets the value as an object.
 The object types are CBLBlob, CBLArray, CBLDictionary, NSNumber, or NSString
 based on the underlying data type; or nil if the value is nil.
 */
@property (nonatomic, readonly, nullable) NSObject* value;

/**
 Gets the value as a string.
 Returns nil if the value is nil, or the value is not a string.
 */
@property (nonatomic, readonly, nullable) NSString* string;

/**
 Gets the value as a number.
 Returns nil if the value is nil, or the value is not a number.
 */
@property (nonatomic, readonly, nullable) NSNumber* number;

/** 
 Gets the value as an integer.
 Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
 Returns 0 if the value is nil or is not a numeric value.
 */
@property (nonatomic, readonly) NSInteger integerValue;

/**
 Gets the value as a long long.
 Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
 Returns 0 if the value is nil or is not a numeric value.
 */
@property (nonatomic, readonly) long long longLongValue;

/** 
 Gets the value as a float.
 Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
 Returns 0.0 if the value is nil or is not a numeric value.
 */
@property (nonatomic, readonly) float floatValue;

/** 
 Gets the value as a double.
 Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
 Returns 0.0 if the value is nil or is not a numeric value.
 */
@property (nonatomic, readonly) double doubleValue;

/** 
 Gets the value as a boolean.
 Returns YES if the value is not nil nor NSNull, and is either `true` or a nonzero number.
 */
@property (nonatomic, readonly) BOOL booleanValue;

/** 
 Gets the value as an NSDate.
 JSON does not directly support dates, so the actual property value must be a string, which is
 then parsed according to the ISO-8601 date format (the default used in JSON.)
 Returns nil if the value is nil, is not a string, or is not parseable as a date.
 NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
 without milliseconds.
 */
@property (nonatomic, readonly, nullable) NSDate* date;

/** 
 Get the value as a CBLBlob.
 Returns nil if the value is nil, or the value is not a CBLBlob.
 */
@property (nonatomic, readonly, nullable) CBLBlob* blob;

/** 
 Get the value as a CBLArray, a mapping object of an array value.
 Returns nil if the value is nil, or the value is not an array.
 */
@property (nonatomic, readonly, nullable) CBLArray* array;

/** 
 Get a property's value as a CBLDictionary, a mapping object of a dictionary value.
 Returns nil if the value is nil, or the value is not a dictionary.
 */
@property (nonatomic, readonly, nullable) CBLDictionary* dictionary;

/** 
 Checks whether the value held by the fragment object exists or is nil value or not.
 */
@property (nonatomic, readonly) BOOL exists;

@end

/** 
 CBLFragment provides read access to data value. CBLFragment also provides
 subscript access by either key or index to the nested values which are wrapped by the
 CBLFragment objects.
 */
@interface CBLFragment : NSObject <CBLFragment, CBLDictionaryFragment,
                                           CBLArrayFragment>

@end

NS_ASSUME_NONNULL_END
