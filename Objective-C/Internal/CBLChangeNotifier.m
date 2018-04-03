//
//  CBLChangeNotifier.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/3/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLChangeNotifier.h"
#import "CBLChangeListenerToken.h"


@implementation CBLChangeNotifier
{
    NSMutableSet<CBLChangeListenerToken*>* _listenerTokens;
}


- (CBLChangeListenerToken*) addChangeListenerWithQueue: (dispatch_queue_t)queue
                                           listener: (void (^)(id))listener
{
    CBLAssertNotNil(listener);

    CBL_LOCK(self) {
        if (!_listenerTokens)
            _listenerTokens = [NSMutableSet set];
        id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                              queue: queue];
        [_listenerTokens addObject: token];
        return token;
    }
}


- (NSUInteger) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBLAssertNotNil(token);

    CBL_LOCK(self) {
        [_listenerTokens removeObject: token];
        return _listenerTokens.count;
    }
}


- (void) postChange: (id)change {
    CBLAssertNotNil(change);

    CBL_LOCK(self) {
        [_listenerTokens makeObjectsPerformSelector: @selector(postChange:) withObject: change];
    }
}


@end
