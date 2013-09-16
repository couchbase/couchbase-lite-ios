//
//  CBLView+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDatabase+Internal.h"
#import "CBLView.h"
#import "CBLQuery.h"


/** Standard query options for views. */
typedef struct CBLQueryOptions {
    __unsafe_unretained id startKey;
    __unsafe_unretained id endKey;
    __unsafe_unretained NSArray* bbox;
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
    BOOL reduceSpecified;
    BOOL reduce;                   // Ignore if !reduceSpecified
    BOOL group;
    BOOL includeDeletedDocs;        // only works with _all_docs, not regular views
    CBLStaleness stale;
} CBLQueryOptions;

extern const CBLQueryOptions kDefaultCBLQueryOptions;


typedef enum {
    kCBLViewCollationUnicode,
    kCBLViewCollationRaw,
    kCBLViewCollationASCII
} CBLViewCollation;


@interface CBLView ()
- (instancetype) initWithDatabase: (CBLDatabase*)db name: (NSString*)name;

- (void) databaseClosing;

@property (readonly) int viewID;
@end


@interface CBLView (Internal)

#if DEBUG  // for unit tests only
- (void) setCollation: (CBLViewCollation)collation;
- (NSArray*) dump;
#endif

//@property CBLContentOptions mapContentOptions;

/** Compiles a view (using the registered CBLViewCompiler) from the properties found in a CouchDB-style design document. */
- (BOOL) compileFromProperties: (NSDictionary*)viewProps
                      language: (NSString*)language;

/** Updates the view's index (incrementally) if necessary.
 @return  200 if updated, 304 if already up-to-date, else an error code */
- (CBLStatus) updateIndex;

/** Queries the view. Does NOT first update the index.
    @param options  The options to use.
    @return  An array of CBLQueryRow. */
- (NSArray*) _queryWithOptions: (const CBLQueryOptions*)options
                        status: (CBLStatus*)outStatus;

@end
