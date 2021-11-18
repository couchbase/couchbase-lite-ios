//
//  CBLQueryChangeNotifier.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 11/18/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLQueryChangeNotifier.h"
#import "CBLQueryObserver.h"
#import "CBLQuery.h"
#import "CBLQueryChange+Internal.h"

@implementation CBLQueryChangeNotifier {
    CBLQueryObserver* _obs;
    NSMutableDictionary* _queryObs;
}

- (CBLChangeListenerToken*) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
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

- (NSUInteger) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBLChangeListenerToken* t = (CBLChangeListenerToken*)token;
    [_queryObs[t.key] stopAndFree];
    
    return [super removeChangeListenerWithToken: token];
}

@end
