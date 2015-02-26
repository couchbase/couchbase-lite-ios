//
//  CBLModelArray.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/12/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLModel;

#if __has_feature(nullability) // Xcode 6.3+
#pragma clang assume_nonnull begin
#else
#define nullable
#define __nullable
#endif


/** An array of CBLModel objects, that's actually backed by document IDs.
    It looks up the model dynamically as each item is accessed.
    This class is used by CBLModel for array-valued properties whose item type is a subclass
    of CBLModel. */
@interface CBLModelArray : NSArray

/** Initializes a model array from an array of document ID strings.
    Returns nil if docIDs contains items that are non-strings, or invalid document IDs. */
- (instancetype) initWithOwner: (CBLModel*)owner
                      property: (nullable NSString*)property
                     itemClass: (nullable Class)itemClass
                        docIDs: (NSArray*)docIDs;

/** Initializes a model array from an array of CBLModels. */
- (instancetype) initWithOwner: (CBLModel*)owner
                      property: (nullable NSString*)property
                     itemClass: (nullable Class)itemClass
                        models: (NSArray*)models;

@property (readonly) NSArray* docIDs;

@end


#if __has_feature(nullability)
#pragma clang assume_nonnull end
#endif
