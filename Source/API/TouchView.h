//
//  TouchView.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDView.h"
@class TouchDatabase, TouchQuery, TDView;


/** A "view" in a TouchDB database -- this is a type of map/reduce index.
    The view can be queried using a TouchQuery. */
@interface TouchView : NSObject
{
    @private
    TouchDatabase* _database;
    TDView* _view;
}

@property (readonly) TouchDatabase* database;

@property (readonly) NSString* name;

@property (readonly) TDMapBlock mapBlock;
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

- (TouchQuery*) query;

@end
