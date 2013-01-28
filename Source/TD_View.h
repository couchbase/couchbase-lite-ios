//
//  TD_View.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TD_Database.h"
#import "TDView.h"


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
    BOOL localSeq;
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
@interface TD_View : NSObject
{
    @private
    TD_Database* __weak _db;
    NSString* _name;
    int _viewID;
    TDMapBlock _mapBlock;
    TDReduceBlock _reduceBlock;
    TDViewCollation _collation;
    TDContentOptions _mapContentOptions;
}

- (void) deleteView;

@property (readonly) TD_Database* database;
@property (readonly) NSString* name;

@property (readonly) TDMapBlock mapBlock;
@property (readonly) TDReduceBlock reduceBlock;

@property TDViewCollation collation;
@property TDContentOptions mapContentOptions;

- (BOOL) setMapBlock: (TDMapBlock)mapBlock
         reduceBlock: (TDReduceBlock)reduceBlock
             version: (NSString*)version;

/** Compiles a view (using the registered TDViewCompiler) from the properties found in a CouchDB-style design document. */
- (BOOL) compileFromProperties: (NSDictionary*)viewProps;

- (void) removeIndex;

/** Is the view's index currently out of date? */
@property (readonly) BOOL stale;

/** Updates the view's index (incrementally) if necessary.
    @return  200 if updated, 304 if already up-to-date, else an error code */
- (TDStatus) updateIndex;

@property (readonly) SequenceNumber lastSequenceIndexed;

/** Queries the view. Does NOT first update the index.
    @param options  The options to use.
    @return  An array of TD_QueryRows. */
- (NSArray*) queryWithOptions: (const TDQueryOptions*)options
                       status: (TDStatus*)outStatus;

/** Utility function to use in reduce blocks. Totals an array of NSNumbers. */
+ (NSNumber*) totalValues: (NSArray*)values;

+ (void) setCompiler: (id<TDViewCompiler>)compiler;
+ (id<TDViewCompiler>) compiler;

@end


/** One result of a view query. */
@interface TD_QueryRow : NSObject
- (id)initWithDocID: (NSString*)docID key: (id)key value: (id)value
         properties: (NSDictionary*)properties;
@property (readonly, nonatomic) id key;
@property (readonly, nonatomic) id value;
@property (readonly, nonatomic) NSString* docID;
@property (readonly, nonatomic) NSDictionary* properties;
@property (readonly, nonatomic) NSDictionary* asJSONDictionary;
@end
