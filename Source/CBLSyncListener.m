//
//  CBLSyncListener.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/3/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLSyncListener.h"
#import "CBLSyncConnection.h"
#import "CouchbaseLite.h"
#import "CBLInternal.h"
#import "BLIPPocketSocketListener.h"
#import "PSWebSocket.h"
#import "CollectionUtils.h"
#import "Logging.h"


@interface CBLSyncListener ()
@property (readwrite) UInt16 port;
@end


@interface CBLSyncListenerImpl : BLIPPocketSocketListener <NSNetServiceDelegate>
@end


@implementation CBLSyncListenerImpl
{
    CBLManager* _manager;
    __weak CBLSyncListener* _facade;
    NSMutableSet* _handlers;
    dispatch_queue_t _queue;
    NSString* _bonjourName, *_bonjourType;
    NSNetService* _netService;
    BOOL _netServicePublished;
}


- (instancetype) initWithManager: (CBLManager*)manager
                          facade: (CBLSyncListener*)facade
{
    NSArray* paths = [manager.allDatabaseNames my_map:^id(NSString* name) {
        return $sprintf(@"/%@/_blipsync", name);
    }];

    self = [super initWithPaths: paths delegate: nil queue: nil];
    if (self) {
        _manager = manager;
        _facade = facade;
        _handlers = [NSMutableSet new];
        _queue = dispatch_queue_create("CBLSyncListener", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}


- (void)dealloc {
    Log(@"DEALLOC %@", self);
    dispatch_sync(_queue, ^{
        for (CBLSyncConnection* handler in _handlers)
            [handler removeObserver: self forKeyPath: @"state"];
    });
}


- (void) blipConnectionDidOpen:(BLIPConnection *)connection {
    NSString* name = ((BLIPPocketSocketConnection*)connection).webSocket.URLRequest.URL.path;
    name = name.stringByDeletingLastPathComponent.lastPathComponent;
    LogTo(Sync, @"OPENED INCOMING %@ from <%@> for %@", connection, connection.URL, name);

    [_manager.backgroundServer waitForDatabaseNamed: name to: ^id(CBLDatabase* db) {
        NSString* name = $sprintf(@"Sync from %@", connection.URL);
        dispatch_queue_t queue = dispatch_queue_create(name.UTF8String, DISPATCH_QUEUE_SERIAL);
        CBLSyncConnection* handler = [[CBLSyncConnection alloc] initWithDatabase: db
                                                                      connection: connection
                                                                           queue: queue];
        [handler addObserver: self forKeyPath: @"state" options: 0 context: (void*)1];
        dispatch_sync(_queue, ^{
            [_handlers addObject: handler];
        });
        return nil;
    }];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (context == (void*)1) {
        CBLSyncConnection* handler = object;
        if (handler.state == kSyncStopped) {
            LogTo(Sync, @"CLOSED INCOMING connection from <%@>", handler.peerURL);
            dispatch_sync(_queue, ^{
                [_handlers removeObject: handler];
                [handler removeObserver: self forKeyPath: @"state"];
            });
        }
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
    _facade.port = self.port;
    if (_bonjourType) {
        dispatch_async(_queue, ^{
            _netService = [[NSNetService alloc] initWithDomain: @""
                                                          type: _bonjourType
                                                          name: _bonjourName
                                                          port: self.port];
            _netService.includesPeerToPeer = YES;
            _netService.delegate = self;
            _netServicePublished = NO;
            [_netService scheduleInRunLoop: [NSRunLoop mainRunLoop] forMode: NSDefaultRunLoopMode];
            [_netService publishWithOptions: 0];
        });
    }
}


- (void) listenerDidStop {
    _facade.port = 0;
    dispatch_async(_queue, ^{
        [_netService stop];
        _netService = nil;
        _netServicePublished = NO;
    });
}


- (void)netServiceDidPublish:(NSNetService *)sender {
    dispatch_async(_queue, ^{
        Log(@"CBLSyncListener: Published Bonjour service '%@'", _netService.name);
        _netServicePublished = YES;
    });
}


- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict {
    Warn(@"CBLSyncListener: Failed to publish Bonjour service '%@': %@", _netService.name, errorDict);
}

@end




@implementation CBLSyncListener
{
    CBLSyncListenerImpl* _impl;
    uint16_t _desiredPort;
}

@synthesize port=_port;

- (instancetype) initWithManager: (CBLManager*)manager port: (uint16_t)port {
    self = [super init];
    if (self) {
        _impl = [[CBLSyncListenerImpl alloc] initWithManager: manager facade: self];
        _desiredPort = port;
    }
    return self;
}

- (void) setBonjourName: (NSString*)name type: (NSString*)type {
    [_impl setBonjourName: name type: type];
}

- (BOOL) start: (NSError**)outError {
    return [_impl acceptOnInterface: nil port: _desiredPort error: outError];
}

- (void) stop {
    [_impl disconnect];
}


@end