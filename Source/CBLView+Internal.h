//
//  CBLView+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDatabase+Internal.h"
#import "CBLView.h"
#import "CBLQuery.h"


/** Standard query options for views. */
@interface CBLQueryOptions : NSObject
{
@public
    const struct CBLGeoRect* bbox;
    unsigned prefixMatchLevel;
    unsigned skip;
    unsigned limit;
    unsigned groupLevel;
    CBLContentOptions content;
    BOOL descending;
    BOOL includeDocs;
    BOOL updateSeq;
    BOOL localSeq;
    BOOL inclusiveStart;
    BOOL inclusiveEnd;
    BOOL reduceSpecified;
    BOOL reduce;                   // Ignore if !reduceSpecified
    BOOL group;
    BOOL fullTextSnippets;
    BOOL fullTextRanking;
    CBLIndexUpdateMode indexUpdateMode;
    CBLAllDocsMode allDocsMode;
}

@property (copy, nonatomic) id startKey;
@property (copy, nonatomic) id endKey;
@property (copy, nonatomic) NSString* startKeyDocID;
@property (copy, nonatomic) NSString* endKeyDocID;
@property (copy, nonatomic) NSArray* keys;
@property (copy, nonatomic) NSPredicate* filter;
@property (copy, nonatomic) NSString* fullTextQuery;

@end

#define kCBLQueryOptionsDefaultLimit UINT_MAX
extern NSString* const kCBLViewChangeNotification;

typedef enum {
    kCBLViewCollationUnicode,
    kCBLViewCollationRaw,
    kCBLViewCollationASCII
} CBLViewCollation;


/** Returns YES if the data is meant as a placeholder for the doc's entire data (a "*") */
BOOL CBLValueIsEntireDoc(NSData* valueData);

BOOL CBLRowPassesFilter(CBLDatabase* db, CBLQueryRow* row, const CBLQueryOptions* options);


@interface CBLView ()
{
    @private
    CBLDatabase* __weak _weakDB;
    NSString* _name;
    int _viewID;
    uint8_t _collation;
}

- (instancetype) initWithDatabase: (CBLDatabase*)db name: (NSString*)name;

- (void) databaseClosing;

@property (readonly) int viewID;
@property (readonly) NSUInteger totalRows;

@end


@interface CBLView (Internal)

+ (void) registerFunctions: (CBLDatabase*)db;

#if DEBUG  // for unit tests only
- (void) setCollation: (CBLViewCollation)collation;
#endif

@property (readonly) NSArray* viewsInGroup;

/** Compiles a view (using the registered CBLViewCompiler) from the properties found in a CouchDB-style design document. */
- (BOOL) compileFromProperties: (NSDictionary*)viewProps
                      language: (NSString*)language;

/** Updates the view's index (incrementally) if necessary.
    If the index is updated, the other views in the viewGroup will be updated as a bonus.
    @return  200 if updated, 304 if already up-to-date, else an error code */
- (CBLStatus) updateIndex;

/** Updates the view's index (incrementally) if necessary. No other groups will be updated.
    @return  200 if updated, 304 if already up-to-date, else an error code */
- (CBLStatus) updateIndexAlone;

@end


@interface CBLView (Querying)

/** Queries the view. Does NOT first update the index.
    @param options  The options to use.
    @return  An array of CBLQueryRow. */
- (NSArray*) _queryWithOptions: (CBLQueryOptions*)options
                        status: (CBLStatus*)outStatus;
#if DEBUG
- (NSArray*) dump;
#endif

@end


@interface CBLDatabase (ViewIndexing)
- (CBLStatus) updateIndexes: (NSArray*)views
                    forView: (CBLView*)forView;
@end
