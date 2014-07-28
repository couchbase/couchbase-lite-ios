//
//  CBLForestBridge.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/14.
//
//

#import <CBForest/CBForest.hh>
extern "C" {
#import "CBLDatabase+Internal.h"
}


CBLStatus CBLStatusFromForestDBStatus(int fdbStatus);


@interface CBLForestBridge : NSObject

/** Gets the parsed body of a revision, including any metadata specified by the content options. */
+ (NSDictionary*) bodyOfNode: (const forestdb::Revision*)revNode
                     options: (CBLContentOptions)options;

+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (VersionedDocument&)doc
                                               revID: (NSString*)revID
                                             options: (CBLContentOptions)options;
+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (VersionedDocument&)doc
                                            sequence: (forestdb::sequence)sequence
                                             options: (CBLContentOptions)options;

/** Stores the body of a revision (including metadata) into a CBL_MutableRevision. */
+ (BOOL) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                          options: (CBLContentOptions)options
                              doc: (VersionedDocument&)doc;

/** Returns the revIDs of all current leaf revisions, in descending order of priority. */
+ (NSArray*) getCurrentRevisionIDs: (VersionedDocument&)doc;

/** Returns a revision & its ancestors as CBL_Revision objects, in reverse chronological order. */
+ (NSArray*) getRevisionHistory: (const forestdb::Revision*)revNode;

/** Returns the revision history as a _revisions dictionary, as returned by the REST API's 
    ?revs=true option. If 'ancestorRevIDs' is present, the revision history will only go back as 
    far as any of the revision ID strings in that array. */
+ (NSDictionary*) getRevisionHistoryOfNode: (const forestdb::Revision*)revNode
                         startingFromAnyOf: (NSArray*)ancestorRevIDs;

@end
