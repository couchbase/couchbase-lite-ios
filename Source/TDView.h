//
//  TDView.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TouchDB/TDDatabase.h>


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


/** Standard query options for views. */
typedef struct TDQueryOptions {
    __unsafe_unretained id startKey;
    __unsafe_unretained id endKey;
    __unsafe_unretained NSArray* keys;
    unsigned skip;
    unsigned limit;
    unsigned groupLevel;
    TDContentOptions content;
    BOOL descending;
    BOOL includeDocs;
    BOOL updateSeq;
    BOOL inclusiveEnd;
    BOOL reduce;
    BOOL group;
    BOOL includeDeletedDocs;        // only works with _all_docs, not regular views
} TDQueryOptions;

extern const TDQueryOptions kDefaultTDQueryOptions;


typedef enum {
    kTDViewCollationUnicode,
    kTDViewCollationRaw,
    kTDViewCollationASCII
} TDViewCollation;


/** An external object that knows how to map source code of some sort into executable functions. */
@protocol TDViewCompiler <NSObject>
- (TDMapBlock) compileMapFunction: (NSString*)mapSource language: (NSString*)language;
- (TDReduceBlock) compileReduceFunction: (NSString*)reduceSource language: (NSString*)language;
@end


/** Represents a view available in a database. */
@interface TDView : NSObject
{
    @private
    TDDatabase* __weak _db;
    NSString* _name;
    int _viewID;
    TDMapBlock _mapBlock;
    TDReduceBlock _reduceBlock;
    TDViewCollation _collation;
    TDContentOptions _mapContentOptions;
}

- (void) deleteView;

@property (readonly) TDDatabase* database;
@property (readonly) NSString* name;

@property (readonly) TDMapBlock mapBlock;
@property (readonly) TDReduceBlock reduceBlock;

@property TDViewCollation collation;
@property TDContentOptions mapContentOptions;

- (BOOL) setMapBlock: (TDMapBlock)mapBlock
         reduceBlock: (TDReduceBlock)reduceBlock
             version: (NSString*)version;

- (void) removeIndex;

/** Is the view's index currently out of date? */
@property (readonly) BOOL stale;

/** Updates the view's index (incrementally) if necessary.
    @return  200 if updated, 304 if already up-to-date, else an error code */
- (TDStatus) updateIndex;

@property (readonly) SequenceNumber lastSequenceIndexed;

/** Queries the view. Does NOT first update the index.
    @param options  The options to use.
    @return  An array of result rows -- each is a dictionary with "key" and "value" keys, and possibly "id" and "doc". */
- (NSArray*) queryWithOptions: (const TDQueryOptions*)options
                       status: (TDStatus*)outStatus;

/** Utility function to use in reduce blocks. Totals an array of NSNumbers. */
+ (NSNumber*) totalValues: (NSArray*)values;

+ (void) setCompiler: (id<TDViewCompiler>)compiler;
+ (id<TDViewCompiler>) compiler;

@end
