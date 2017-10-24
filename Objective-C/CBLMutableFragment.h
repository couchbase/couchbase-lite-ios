//
//  CBLMutableFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
 Gets the value from or sets the value to the fragment object. The object types are CBLMutableArray,
 CBLBlob, CBLMutableDictionary, NSNumber, NSString, NSNull, or nil.
 */
@property (nonatomic, nullable) NSObject* value;

/** 
 Get the value as a CBLMutableArray, a mapping object of an array value.
 Returns nil if the value is nil, or the value is not an array.
 */
@property (nonatomic, readonly, nullable) CBLMutableArray* array;

/** 
 Get a property's value as a CBLMutableDictionary, a mapping object of a dictionary value.
 Returns nil if the value is nil, or the value is not a dictionary.
 */
@property (nonatomic, readonly, nullable) CBLMutableDictionary* dictionary;

@end

/** 
 CBLMutableFragment provides read and write access to data value. CBLMutableFragment also provides
 subscript access by either key or index to the nested values which are wrapped by
 CBLMutableFragment objects.
 */
@interface CBLMutableFragment : CBLFragment <CBLMutableFragment, CBLMutableDictionaryFragment, CBLMutableArrayFragment>

@end

NS_ASSUME_NONNULL_END
