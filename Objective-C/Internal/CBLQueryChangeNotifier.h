//
//  CBLQueryChangeNotifier.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 11/18/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLChangeNotifier.h"

@class CBLQuery;
@class CBLQueryChange;

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryChangeNotifier : CBLChangeNotifier

/** Starts an observer and listener on the queue. */
- (CBLChangeListenerToken*) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                              listener: (void (^)(CBLQueryChange*))listener
                                                 queue: (CBLQuery*)query
                                           columnNames: (NSDictionary *)columnNames;

/** Removes the observer and listener*/
- (NSUInteger) removeChangeListenerWithToken: (id<CBLListenerToken>)token;

@end

NS_ASSUME_NONNULL_END
