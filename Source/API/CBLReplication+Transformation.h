//
//  CBLReplication+Transformation.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/14/14.
//  Copyright (c) 2014 Couchbase, Inc. All rights reserved.

#import <CouchbaseLite/CouchbaseLite.h>


/** A callback block for transforming revision bodies during replication.
    See CBLReplication.propertiesTransformationBlock's documentation for details. */
typedef NSDictionary *(^CBLPropertiesTransformationBlock)(NSDictionary* doc);


@interface CBLReplication (Transformation)

/** Optional callback for transforming document bodies during replication; can be used to encrypt documents stored on the remote server, for example.
    In a push replication, the block is called with document properties from the local database, and the transformed properties are what will be uploaded to the server.
    In a pull replication, the block is called with document properties downloaded from the server, and the transformed properties are what will be stored in the local database.
    The block takes an NSDictionary containing the document's properties (including the "_id" and "_rev" metadata), and returns a dictionary of transformed properties. It may return the input dictionary if it has no changes to make.
    The transformation MUST preserve the values of any keys whose names begin with an underscore ("_")!
    The block will be called on the background replicator thread, NOT on the CBLReplication's thread, so it shouldn't directly access any Couchbase Lite objects. */
@property (strong) CBLPropertiesTransformationBlock propertiesTransformationBlock;

@end
