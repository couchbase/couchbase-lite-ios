//
//  CBLMutableFragment.h
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
#import "CBLMutableArray.h"
#import "CBLMutableArrayFragment.h"
#import "CBLMutableDictionary.h"
#import "CBLMutableDictionaryFragment.h"
#import "CBLFragment.h"

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLMutableFragment protocol provides read and write access to the data value wrapped by a
 fragment object.
 */
@protocol CBLMutableFragment <CBLFragment>

/** 
 Gets value from or sets the value to the fragment object.
 */
@property (nonatomic, nullable) NSObject* value;

/**
 Gets the value as string or sets the string value to the fragment object.
 */
@property (nonatomic, nullable) NSString* string;

/**
 Gets the value as number or sets the number value to the fragment object.
 */
@property (nonatomic, nullable) NSNumber* number;

/**
 Gets the value as integer or sets the integer value to the fragment object.
 */
@property (nonatomic) NSInteger integerValue;

/**
 Gets the value as long long or sets the long long value to the fragment object.
 */
@property (nonatomic) long long longLongValue;

/**
 Gets the value as float or sets the float value to the fragment object.
 */
@property (nonatomic) float floatValue;

/**
 Gets the value as double or sets the double value to the fragment object.
 */
@property (nonatomic) double doubleValue;

/**
 Gets the value as boolean or sets the boolean value to the fragment object.
 */
@property (nonatomic) BOOL booleanValue;

/**
 Gets the value as date or sets the date value to the fragment object.
 */
@property (nonatomic, nullable) NSDate* date;

/**
 Gets the value as blob or sets the blob value to the fragment object.
 */
@property (nonatomic, nullable) CBLBlob* blob;

/**
 Gets the value as array or sets the array value to the fragment object.
 */
@property (nonatomic, nullable) CBLMutableArray* array;

/**
 Gets the value as dictionary or sets the dictionary value to the fragment object.
 */
@property (nonatomic, nullable) CBLMutableDictionary* dictionary;

@end

/** 
 CBLMutableFragment provides read and write access to data value. CBLMutableFragment also provides
 subscript access by either key or index to the nested values which are wrapped by
 CBLMutableFragment objects.
 */
@interface CBLMutableFragment : CBLFragment <CBLMutableFragment, CBLMutableDictionaryFragment, CBLMutableArrayFragment>

@end

NS_ASSUME_NONNULL_END
