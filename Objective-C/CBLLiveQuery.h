//
//  CBLLiveQuery.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/15/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"

NS_ASSUME_NONNULL_BEGIN


// *** WARNING ***  This is an unofficial placeholder API. It WILL change.


/** A CBLQuery subclass that automatically refreshes the result rows every time the database
    changes. All you need to do is use KVO to observe changes to the .rows property. */
@interface CBLLiveQuery : CBLQuery

/** The shortest interval at which the query will update, regardless of how often the
    database changes. Defaults to 0.2 sec. Increase this if the query is expensive and
    the database updates frequently, to limit CPU consumption. */
@property (nonatomic) NSTimeInterval updateInterval;

/** Starts observing database changes. The .rows property will now update automatically. (You 
    usually don't need to call this yourself, since accessing or observing the .rows property will
    call -start for you.) */
- (void) start;

/** Stops observing database changes. Calling -start or .rows will restart it. */
- (void) stop;

/** The current query results; this updates as the database changes, and can be observed using KVO.
    Its value will be nil until the initial asynchronous query finishes. */
@property (readonly, nullable, nonatomic) NSArray<CBLQueryRow*>* rows;

/** If non-nil, the error of the last execution of the query.
    If nil, the last execution of the query was successful. */
@property (readonly, nullable, nonatomic) NSError* lastError;

@end

NS_ASSUME_NONNULL_END
