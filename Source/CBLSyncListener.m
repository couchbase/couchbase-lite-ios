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
    dispatch_queue_t _queue;
    NSString* _bonjourName, *_bonjourType;
    NSNetService* _netService;
    BOOL _netServicePublished;
}

- (instancetype) initWithDatabase: (CBLDatabase*)db
                             path: (NSString*)path
{
    self = [super initWithPath: path delegate: nil queue: nil];
    if (self) {
        _db = db;
        _handlers = [NSMutableSet new];
        _queue = dispatch_queue_create("CBLSyncListener", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void) blipConnectionDidOpen:(BLIPConnection *)connection {
    dispatch_async(_queue, ^{
        LogTo(Sync, @"OPENED INCOMING %@ from <%@>", connection, connection.URL);
        NSString* name = $sprintf(@"Sync from %@", connection.URL);
        dispatch_queue_t queue = dispatch_queue_create(name.UTF8String, DISPATCH_QUEUE_SERIAL);
        CBLSyncConnection* handler = [[CBLSyncConnection alloc] initWithDatabase: _db
                                                                connection: connection
                                                                     queue: queue];
        [_handlers addObject: handler];
        [handler addObserver: self forKeyPath: @"state" options: 0 context: (void*)1];
    });
}

- (void) forgetHandler: (CBLSyncConnection*)handler {
    dispatch_async(_queue, ^{
        LogTo(Sync, @"CLOSED INCOMING connection from <%@>", handler.peerURL);
        [handler removeObserver: self forKeyPath: @"state"];
        [_handlers removeObject: handler];
    });
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

#pragma mark - BONJOUR:

- (void) setBonjourName: (NSString*)name type: (NSString*)type {
    dispatch_async(_queue, ^{
        _bonjourName = name;
        _bonjourType = type;
    });
}

- (NSString*) bonjourName {
    return _netServicePublished ? _netService.name : nil;
}

- (void) listenerDidStart {
    dispatch_async(_queue, ^{
        if (_bonjourType) {
            _netService = [[NSNetService alloc] initWithDomain: @""
                                                          type: _bonjourType
                                                          name: _bonjourName
                                                          port: self.port];
            _netService.includesPeerToPeer = YES;
            _netService.delegate = self;
            _netServicePublished = NO;
            [_netService scheduleInRunLoop: [NSRunLoop mainRunLoop] forMode: NSDefaultRunLoopMode];
            [_netService publishWithOptions: 0];
        }
    }
}

- (void) listenerDidStop {
    dispatch_async(_queue, ^{
        [_netService stop];
        _netService = nil;
        _netServicePublished = NO;
    }
}


- (void)netServiceDidPublish:(NSNetService *)sender {
    dispatch_async(_queue, ^{
        Log(@"CBLSyncListener: Published Bonjour service '%@'", self.name);
        _netServicePublished = YES;
    }
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict {
    Warn(@"CBLSyncListener: Failed to publish Bonjour service '%@': %@", self.name, errorDict);
}

@end
