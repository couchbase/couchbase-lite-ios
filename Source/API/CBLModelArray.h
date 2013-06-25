//
//  CBLModelArray.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/12/13.
//
//

#import <Foundation/Foundation.h>
@class CBLModel;


/** An array of CBLModel objects, that's actually backed by document IDs.
    It looks up the model dynamically as each item is accessed.
    This class is used by CBLModel for array-valued properties whose item type is a subclass
    of CBLModel. */
@interface CBLModelArray : NSArray

/** Initializes a model array from an array of document ID strings.
    Returns nil if docIDs contains items that are non-strings, or invalid document IDs. */
- (instancetype) initWithOwner: (CBLModel*)owner
                      property: (NSString*)property
                     itemClass: (Class)itemClass
                        docIDs: (NSArray*)docIDs;

/** Initializes a model array from an array of CBLModels. */
- (instancetype) initWithOwner: (CBLModel*)owner
                      property: (NSString*)property
                     itemClass: (Class)itemClass
                        models: (NSArray*)models;

@property (readonly) NSArray* docIDs;

@end
