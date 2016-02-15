//
//  CBL_StorageTypes.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/20/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLStatus.h"
#import "CBLQuery.h"
@class CBL_Revision;


/** Predicate block that can filter rows of a query result. */
typedef BOOL (^CBLQueryRowFilter)(CBLQueryRow*);

/** Document validation callback, passed to the insertion methods. */
typedef CBLStatus(^CBL_StorageValidationBlock)(CBL_Revision* newRev,
                                               CBL_Revision* prev,
                                               NSString* parentRevID,
                                               NSError** outError);


/** Standard query options for views. */
@interface CBLQueryOptions : NSObject
{
    @public
    const struct CBLGeoRect* bbox;
    unsigned prefixMatchLevel;
    unsigned skip;
    unsigned limit;
    unsigned groupLevel;
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
@property (copy, nonatomic) CBLQueryRowFilter filter;
@property (copy, nonatomic) NSString* fullTextQuery;

@property (readonly) id minKey;     // startKey, or endKey if descending=YES
@property (readonly) id maxKey;     // Max of the key range, taking into account prefixMatchLevel

/** Checks whether limit=0 or keys=[] */
@property (readonly) BOOL isEmpty;

@end

// Default value of CBLQueryOptions.limit
#define kCBLQueryOptionsDefaultLimit UINT_MAX


/** Options for _changes feed (-changesSinceSequence:). */
typedef struct CBLChangesOptions {
    unsigned limit;
    BOOL includeDocs;
    BOOL includeConflicts;
    BOOL sortBySequence;
    BOOL descending;
} CBLChangesOptions;

extern const CBLChangesOptions kDefaultCBLChangesOptions;
