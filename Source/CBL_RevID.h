//
//  CBL_RevID.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/18/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLBase.h"

NS_ASSUME_NONNULL_BEGIN

/** A revision ID. We support different forms of these; this class is abstract. */
@interface CBL_RevID : NSObject <NSCopying>

+ (instancetype) fromString: (NSString*)str;
+ (instancetype) fromData: (NSData*)data;

@property (readonly) NSString* asString;
@property (readonly) NSData* asData;

@property (readonly) unsigned generation;
@property (readonly, nullable) NSString* suffix;

/** Correctly collates revision IDs, by generation and then by suffix. */
- (NSComparisonResult)compare: (CBL_RevID*)other;

@end


/** Standard CouchDB-style revID of the form "generation-digest" */
@interface CBL_TreeRevID : CBL_RevID

- (instancetype) initWithData: (NSData*)data;

/** Generates a new revID for a revision given its JSON body, deleted flag, and the parent's ID. */
+ (CBL_RevID*) revIDForJSON: (NSData*)json
                    deleted: (BOOL)deleted
                  prevRevID: (nullable CBL_RevID*)prevID;

/** Turns an array of CBL_RevIDs into a _revisions dictionary, as returned by the REST API's
    ?revs=true option. */
+ (NSDictionary*) makeRevisionHistoryDict: (NSArray<CBL_RevID*>*)history;

/** Converts a _revisions dictionary back into an array of CBL_RevIDs. */
+ (NSArray<CBL_RevID*>*) parseRevisionHistoryDict: (NSDictionary*)dict;

@end


@interface NSString (CBL_RevID)
@property (readonly) CBL_RevID* cbl_asRevID;
@end

@interface NSArray (CBL_RevID)
@property (readonly) NSArray<CBL_RevID*>* cbl_asRevIDs;
@property (readonly) NSArray<CBL_RevID*>* cbl_asMaybeRevIDs;
@end


#if DEBUG
#define AssertContainsRevIDs(ARRAY)     (void)$castArrayOf(CBL_RevID, (ARRAY))
#else
#define AssertContainsRevIDs(ARRAY)     ({ })
#endif


/** SQLite-compatible collation (comparison) function for revision IDs. */
int CBLCollateRevIDs(void * _Nullable context,
                     int len1, const void * chars1,
                     int len2, const void * chars2);

NS_ASSUME_NONNULL_END
