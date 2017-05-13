//
//  CBLFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLArray.h"
#import "CBLArrayFragment.h"
#import "CBLDictionary.h"
#import "CBLDictionaryFragment.h"
#import "CBLReadOnlyFragment.h"

NS_ASSUME_NONNULL_BEGIN

/** CBLFragment protocol provides read and write access to the data value wrapped by a 
    fragment object. */
@protocol CBLFragment <CBLReadOnlyFragment>

/** Gets the value from or sets the value to the fragment object. The object types are CBLArray,
    CBLBlob, CBLDictionary, NSNumber, NSString, NSNull, or nil. */
@property (nonatomic, nullable) NSObject* value;

/** Get the value as a CBLArray, a mapping object of an array value. 
    Returns nil if the value is nil, or the value is not an array. */
@property (nonatomic, readonly, nullable) CBLArray* array;

/** Get a property's value as a CBLDictionary, a mapping object of a dictionary value.
    Returns nil if the value is nil, or the value is not a dictionary. */
@property (nonatomic, readonly, nullable) CBLDictionary* dictionary;

@end

/** CBLFragment provides read and write access to data value. CBLFragment also provides
    subscript access by either key or index to the nested values which are wrapped by 
    CBLFragment objects. */
@interface CBLFragment : CBLReadOnlyFragment <CBLFragment, CBLDictionaryFragment, CBLArrayFragment>

@end

NS_ASSUME_NONNULL_END
