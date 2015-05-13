//
//  CBLSyncListener.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/3/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLSyncListener.h"
#import "CBLSyncConnection.h"
#import "CollectionUtils.h"
#import "Logging.h"


@implementation CBLSyncListener
{
    CBLDatabase* _db;
    NSMutableSet* _handlers;
}

- (instancetype) initWithDatabase: (CBLDatabase*)db
                             path: (NSString*)path
{
    self = [super initWithPath: path delegate: nil queue: nil];
    if (self) {
        _db = db;
        _handlers = [NSMutableSet new];
    }
    return self;
}

- (void) blipConnectionDidOpen:(BLIPConnection *)connection {
    LogTo(Sync, @"OPENED INCOMING %@ from <%@>", connection, connection.URL);
    NSString* name = $sprintf(@"Sync from %@", connection.URL);
    dispatch_queue_t queue = dispatch_queue_create(name.UTF8String, DISPATCH_QUEUE_SERIAL);
    CBLSyncConnection* handler = [[CBLSyncConnection alloc] initWithDatabase: _db
                                                            connection: connection
                                                                 queue: queue];
    [_handlers addObject: handler];
    [handler addObserver: self forKeyPath: @"state" options: 0 context: (void*)1];
}

- (void) forgetHandler: (CBLSyncConnection*)handler {
    LogTo(Sync, @"CLOSED INCOMING connection from <%@>", handler.peerURL);
    [handler removeObserver: self forKeyPath: @"state"];
    [_handlers removeObject: handler];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (context == (void*)1) {
        CBLSyncConnection* handler = object;
        if (handler.state == kSyncStopped)
            [self forgetHandler: handler];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
