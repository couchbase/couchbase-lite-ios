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
#import "CBLDictionaryFragment.h"
#import "CBLReadOnlyFragment.h"
#import "CBLSubdocument.h"

NS_ASSUME_NONNULL_BEGIN

/** CBLFragment protocol provides read and write access to the data value wrapped by 
    a fragment object. */
@protocol CBLFragment <CBLReadOnlyFragment>

/** Gets or sets the value as an object. The object types are CBLBlob, CBLReadOnlyArray, 
    CBLReadOnlyDictionary, NSNumber, or NSString based on the underlying data type; or nil 
    if the value is nil. */
@property (nonatomic, nullable) NSObject* value;

/** Get the value as a CBLArray, a mapping object of an array value. 
    Returns nil if the value is nil, or the value is not an array. */
@property (nonatomic, readonly, nullable) CBLArray* array;

/** Get a property's value as a CBLSubdocument, a mapping object of a dictionary value.
    Returns nil if the value is nil, or the value is not a dictionary. */
@property (nonatomic, readonly, nullable) CBLSubdocument* subdocument;

@end

/** CBLFragment provides read and write access to data value. CBLFragment also provides
    subscript access by either key or index to the nested values which are wrapped by the
    CBLFragment objects. */
@interface CBLFragment : CBLReadOnlyFragment <CBLFragment, CBLDictionaryFragment, CBLArrayFragment>

@end

NS_ASSUME_NONNULL_END
