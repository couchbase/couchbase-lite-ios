//
//  CBLDocumentChangeNotifier.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/3/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLChangeNotifier.h"
@class CBLDatabase;
@class CBLDocumentChange;

NS_ASSUME_NONNULL_BEGIN


/**
 A subclass of CBLChangeNotifier that manages document change notifications.
 It manages the underlying C4DocumentObserver and posts the CBLDocumentChange notifications itself.
*/
@interface CBLDocumentChangeNotifier : CBLChangeNotifier<CBLDocumentChange*>

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       documentID: (NSString*)documentID;

/** Immediately stops the C4DocumentObserver. No more notifications will be sent. */
- (void) stop;

@end

NS_ASSUME_NONNULL_END
