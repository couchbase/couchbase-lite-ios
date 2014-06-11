//
//  CBForestVersions+JSON.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/14.
//
//

#import <CBForest/CBForest.hh>
#import "CBLDatabase+Internal.h"


@interface CBLForestBridge : NSObject

+ (NSString*) revIDToString: (forestdb::revid)revID;

/** Gets the parsed body of a revision, including any metadata specified by the content options. */
+ (NSDictionary*) bodyOfNode: (const forestdb::RevNode*)node
                     options: (CBLContentOptions)options;

+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (VersionedDocument&)doc
                                               revID: (NSString*)revID
                                             options: (CBLContentOptions)options;

/** Stores the body of a revision (including metadata) into a CBL_MutableRevision. */
+ (BOOL) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                          options: (CBLContentOptions)options
                             doc: (VersionedDocument&)doc;

+ (NSArray*) getCurrentRevisionIDs: (VersionedDocument&)doc;

/** Returns a revision & its ancestors as CBL_Revision objects, in reverse chronological order. */
+ (NSArray*) getRevisionHistory: (const forestdb::RevNode*)node;

/** Returns the revision history as a _revisions dictionary, as returned by the REST API's 
    ?revs=true option. If 'ancestorRevIDs' is present, the revision history will only go back as 
    far as any of the revision ID strings in that array. */
+ (NSDictionary*) getRevisionHistoryOfNode: (const forestdb::RevNode*)node
                         startingFromAnyOf: (NSArray*)ancestorRevIDs;

/** Returns IDs of local revisions of the same document, that have a lower generation number.
    Does not return revisions whose bodies have been compacted away, or deletion markers. */
+ (NSArray*) getPossibleAncestorRevisionIDs: (NSString*)revID
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments
                                        doc: (VersionedDocument&)doc;

+ (NSString*) findCommonAncestorOf: (NSString*)revID
                        withRevIDs: (NSArray*)revIDs
                               doc: (VersionedDocument&)doc;

@end
