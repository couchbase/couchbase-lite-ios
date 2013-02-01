//
//  CBL_View.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBL_Database.h"
#import "CBLView.h"


/** Standard query options for views. */
typedef struct CBLQueryOptions {
    __unsafe_unretained id startKey;
    __unsafe_unretained id endKey;
    __unsafe_unretained NSArray* keys;
    unsigned skip;
    unsigned limit;
    unsigned groupLevel;
    CBLContentOptions content;
    BOOL descending;
    BOOL includeDocs;
    BOOL updateSeq;
    BOOL localSeq;
    BOOL inclusiveEnd;
    BOOL reduce;
    BOOL group;
    BOOL includeDeletedDocs;        // only works with _all_docs, not regular views
} CBLQueryOptions;

extern const CBLQueryOptions kDefaultCBLQueryOptions;


typedef enum {
    kCBLViewCollationUnicode,
    kCBLViewCollationRaw,
    kCBLViewCollationASCII
} CBLViewCollation;


/** Represents a view available in a database. */
@interface CBL_View : NSObject
{
    @private
    CBL_Database* __weak _db;
    NSString* _name;
    int _viewID;
    CBLMapBlock _mapBlock;
    CBLReduceBlock _reduceBlock;
    CBLViewCollation _collation;
    CBLContentOptions _mapContentOptions;
}

- (void) deleteView;

@property (readonly) CBL_Database* database;
@property (readonly) NSString* name;

@property (readonly) CBLMapBlock mapBlock;
@property (readonly) CBLReduceBlock reduceBlock;

@property CBLViewCollation collation;
@property CBLContentOptions mapContentOptions;

- (BOOL) setMapBlock: (CBLMapBlock)mapBlock
         reduceBlock: (CBLReduceBlock)reduceBlock
             version: (NSString*)version;

/** Compiles a view (using the registered CBLViewCompiler) from the properties found in a CouchDB-style design document. */
- (BOOL) compileFromProperties: (NSDictionary*)viewProps
                      language: (NSString*)language;

- (void) removeIndex;

/** Is the view's index currently out of date? */
@property (readonly) BOOL stale;

/** Updates the view's index (incrementally) if necessary.
    @return  200 if updated, 304 if already up-to-date, else an error code */
- (CBLStatus) updateIndex;

@property (readonly) SequenceNumber lastSequenceIndexed;

/** Queries the view. Does NOT first update the index.
    @param options  The options to use.
    @return  An array of CBL_QueryRows. */
- (NSArray*) queryWithOptions: (const CBLQueryOptions*)options
                       status: (CBLStatus*)outStatus;

/** Utility function to use in reduce blocks. Totals an array of NSNumbers. */
+ (NSNumber*) totalValues: (NSArray*)values;

@end


/** One result of a view query. */
@interface CBL_QueryRow : NSObject
- (id)initWithDocID: (NSString*)docID key: (id)key value: (id)value
         properties: (NSDictionary*)properties;
@property (readonly, nonatomic) id key;
@property (readonly, nonatomic) id value;
@property (readonly, nonatomic) NSString* docID;
@property (readonly, nonatomic) NSDictionary* properties;
@property (readonly, nonatomic) NSDictionary* asJSONDictionary;
@end
