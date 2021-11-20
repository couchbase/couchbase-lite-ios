//
//  CBLQueryChangeNotifier.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLQueryChangeNotifier.h"
#import "CBLQueryObserver.h"
#import "CBLQuery.h"
#import "CBLQueryChange+Internal.h"

@implementation CBLQueryChangeNotifier {
    CBLQueryObserver* _obs;
    NSMutableDictionary* _queryObs;
}

- (CBLChangeListenerToken*) addQueryChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                                   listener: (void (^)(CBLQueryChange*))listener
                                                      queue: (CBLQuery*)query
                                                columnNames: (NSDictionary *)columnNames {
    CBLChangeListenerToken* token = [super addChangeListenerWithQueue: queue listener: listener];
    NSString* uuid = [[NSUUID UUID] UUIDString];
    token.key = uuid;
    
    CBLQueryObserver* obs = [[CBLQueryObserver alloc] initWithQuery: query
                                                        columnNames: columnNames
                                                              token: token];
    // start immediately
    [obs start];
    
    _queryObs[uuid] = obs;
    
    return token;
}

- (void) removeQueryChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBLChangeListenerToken* t = (CBLChangeListenerToken*)token;
    [_queryObs[t.key] stopAndFree];
    
    [super removeChangeListenerWithToken: token];
}

@end
