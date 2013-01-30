//
//  TDView.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDatabase, TDQuery;


typedef void (^TDMapEmitBlock)(id key, id value);

/** A "map" function called when a document is to be added to a view.
    @param doc  The contents of the document being analyzed.
    @param emit  A block to be called to add a key/value pair to the view. Your block can call it zero, one or multiple times. */
typedef void (^TDMapBlock)(NSDictionary* doc, TDMapEmitBlock emit);

/** A "reduce" function called to summarize the results of a view.
	@param keys  An array of keys to be reduced (or nil if this is a rereduce).
	@param values  A parallel array of values to be reduced, corresponding 1::1 with the keys.
	@param rereduce  YES if the input values are the results of previous reductions.
	@return  The reduced value; almost always a scalar or small fixed-size object. */
typedef id (^TDReduceBlock)(NSArray* keys, NSArray* values, BOOL rereduce);


#define MAPBLOCK(BLOCK) ^(NSDictionary* doc, void (^emit)(id key, id value)){BLOCK}
#define REDUCEBLOCK(BLOCK) ^id(NSArray* keys, NSArray* values, BOOL rereduce){BLOCK}


/** A "view" in a TouchDB database -- essentially a persistent index managed by map/reduce.
    The view can be queried using a TDQuery. */
@interface TDView : NSObject

/** The database that owns this view. */
@property (readonly) TDDatabase* database;

/** The name of the view. */
@property (readonly) NSString* name;

/** The map function that controls how index rows are created from documents. */
@property (readonly) TDMapBlock mapBlock;

/** The optional reduce function, which aggregates together multiple rows. */
@property (readonly) TDReduceBlock reduceBlock;

/** Defines or deletes a view.
    The view's definition is given as an Objective-C block (or NULL to delete the view). The body of the block should call the 'emit' block (passed in as a paramter) for every key/value pair it wants to write to the view.
    Since the function itself is obviously not stored in the database (only a unique string idenfitying it), you must re-define the view on every launch of the app! If the database needs to rebuild the view but the function hasn't been defined yet, it will fail and the view will be empty, causing weird problems later on.
    It is very important that this block be a law-abiding map function! As in other languages, it must be a "pure" function, with no side effects, that always emits the same values given the same input document. That means that it should not access or change any external state; be careful, since blocks make that so easy that you might do it inadvertently!
    The block may be called on any thread, or on multiple threads simultaneously. This won't be a problem if the code is "pure" as described above, since it will as a consequence also be thread-safe. */
- (BOOL) setMapBlock: (TDMapBlock)mapBlock
         reduceBlock: (TDReduceBlock)reduceBlock
             version: (NSString*)version;

/** Defines or deletes a view that has no reduce function.
    See -setMapBlock:reduceBlock:version: for more details. */
- (BOOL) setMapBlock: (TDMapBlock)mapBlock
             version: (NSString*)version;

/** Creates a new query object for this view. The query can be customized and then executed. */
- (TDQuery*) query;

@end
