//
//  CBLChangeNotifier.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
