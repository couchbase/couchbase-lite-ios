//
//  CBLTimeSeries.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/26/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLBase.h"
@class CBLDatabase, CBLReplication;


NS_ASSUME_NONNULL_BEGIN

/** Efficiently stores small time-stamped JSON values into a database,
    and can replicate them to a server (purging them as soon as they're pushed.) */
@interface CBLTimeSeries : NSObject

/** Initializes a new CBLTimeSeries.
    @param db  The database to store events in.
    @param docType  The document "type" property to use. Must be non-nil, and must not be used by
                    any other documents or time-series in the database.
    @return error  On return, the error if any. */
- (nullable instancetype) initWithDatabase: (CBLDatabase*)db
                                   docType: (NSString*)docType
                                     error: (NSError**)outError;

/** The "type" property that will be added to documents. */
@property (readonly) NSString* docType;

/** A prefix for the IDs of documents created by this object.
    Defaults to "TS-" + docType + "-". */
@property (copy) NSString* docIDPrefix;

/** The latest error encountered. 
    Observable. (Note: May be modified on any thread.) */
@property (readonly, nullable) NSError* lastError;

/** Adds an event, timestamped with the current time. Can be called on any thread. */
- (void) addEvent: (CBLJSONDict*)event;

/** Adds an event with a custom timestamp (which must be greater than the last timestamp.)
    Can be called on any thread. */
- (void) addEvent: (CBLJSONDict*)event atTime: (CFAbsoluteTime)time;

/** Writes all pending events to documents asynchronously, then calls the onFlushed block
    (with parameter YES on success, NO if there were any errors.)
    Can be called on any thread. */
- (void) flushAsync: (void(^)(BOOL))onFlushed;

/** Writes all pending events to documents before returning.
    Must be called on the database's thread.
    @return  YES on success, NO if there were any errors. */
- (BOOL) flush;

/** Stops the CBLTimeSeries, immediately flushing all pending events. */
- (void) stop;


//// REPLICATION:

/** Creates, but does not start, a new CBLReplication to push the events to a remote database.
    You can customize the replication's properties before starting it, but don't alter the
    filter or remove the existing customProperties.
    @param remoteURL  The URL of the remote database to push to.
    @param purgeWhenPushed  If YES, time-series documents will be purged from the local database
            immediately after they've been pushed. Use this if you don't need them anymore.
    @return  The CBLReplication instance. */
- (CBLReplication*) createPushReplication: (NSURL*)remoteURL
                          purgeWhenPushed: (BOOL)purgeWhenPushed;


//// QUERYING:

/** Enumerates the events stored in the database from time t0 to t1, inclusive.
    Each event returned from the NSEnumerator is an NSDictionary, as provided to -addEvent,
    with a key "t" whose value is the absolute time as an NSDate.
    @param startDate  The starting time (or nil to start from the beginning.)
    @param endDate  The ending time (or nil to continue till the end.)
    @param outError  On return, any error that occurred starting the enumeration.
    @return  An enumerator of NSDictionaries, one per event. */
- (NSEnumerator<CBLJSONDict*>*) eventsFromDate: (nullable NSDate*)startDate
                                        toDate: (nullable NSDate*)endDate
                                         error: (NSError**)outError;

/** Callback for single-document enumeration.
    @param event  The event dictionary.
    @param time  The absolute timestamp.
    @param stop  Set the pointed-to BOOL to YES to stop enumeration. */
typedef void (^CBLTimeSeriesEnumerationBlock)(CBLJSONDict* event, CFAbsoluteTime time, BOOL *stop);

/** Enumerates the events in a single time-series document. Useful in map blocks.
    @param doc  The body of the document to enumerate.
    @param block  A callback to be invoked on every event.
    @return  NO if the document is not a valid time-series, otherwise YES. */
+ (BOOL) enumerateEventsInDocument: (CBLJSONDict*)doc
                        usingBlock: (CBLTimeSeriesEnumerationBlock)block;

@end

NS_ASSUME_NONNULL_END
