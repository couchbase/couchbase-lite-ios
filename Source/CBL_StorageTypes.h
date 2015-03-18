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


/** Options for what metadata to include in document bodies */
typedef unsigned CBLContentOptions;
enum {
    kCBLIncludeAttachments = 1,              // adds inline bodies of attachments
    kCBLIncludeConflicts = 2,                // adds '_conflicts' property (if relevant)
    kCBLIncludeRevs = 4,                     // adds '_revisions' property
    kCBLIncludeRevsInfo = 8,                 // adds '_revs_info' property
    kCBLIncludeLocalSeq = 16,                // adds '_local_seq' property
    kCBLLeaveAttachmentsEncoded = 32,        // i.e. don't decode
    kCBLBigAttachmentsFollow = 64,           // i.e. add 'follows' key instead of data for big ones
    kCBLNoBody = 128,                        // omit regular doc body properties
};


/** Predicate block that can filter rows of a query result. */
typedef BOOL (^CBLQueryRowFilter)(CBLQueryRow*);

/** Block-based iterator for returning query results. 
    Returns next row every time it's called, then returns nil at the end. */
typedef CBLQueryRow* (^CBLQueryIteratorBlock)(void);

/** Document validation callback, passed to the insertion methods. */
typedef CBLStatus(^CBL_StorageValidationBlock)(CBL_Revision* newRev,
                                               CBL_Revision* prev,
                                               NSString* parentRevID);



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
@property (copy, nonatomic) CBLQueryRowFilter filter;
@property (copy, nonatomic) NSString* fullTextQuery;

@end

// Default value of CBLQueryOptions.limit
#define kCBLQueryOptionsDefaultLimit UINT_MAX


/** Options for _changes feed (-changesSinceSequence:). */
typedef struct CBLChangesOptions {
    unsigned limit;
    CBLContentOptions contentOptions;
    BOOL includeDocs;
    BOOL includeConflicts;
    BOOL sortBySequence;
} CBLChangesOptions;

extern const CBLChangesOptions kDefaultCBLChangesOptions;
