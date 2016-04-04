//
//  CBLSyncListener.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/3/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLSyncListener.h"
#import "CBLListener+Internal.h"
#import "CBLSyncConnection.h"
#import "BLIPRequest.h"
#import "CouchbaseLite.h"
#import "CBLInternal.h"
#import "BLIPPocketSocketListener.h"
#import "PSWebSocket.h"
#import "CollectionUtils.h"


@interface CBLSyncListener ()
@property (readwrite) UInt16 port;
@property (readwrite) NSUInteger connectionCount;
@property (readwrite, copy) NSString* bonjourName;
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
    NSData* _txtData;
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
    LogTo(Listener, @"DEALLOC %@", self);
    dispatch_sync(_queue, ^{
        for (CBLSyncConnection* handler in _handlers)
            [handler removeObserver: self forKeyPath: @"state"];
    });
}


- (BOOL) checkClientCertificateAuthentication: (SecTrustRef)trust
                                  fromAddress: (NSData*)address
{
    id<CBLListenerDelegate> delegate = _facade.delegate;
    if ([delegate respondsToSelector: @selector(authenticateConnectionFromAddress:withTrust:)]) {
        return [delegate authenticateConnectionFromAddress: address withTrust: trust] != nil;
    }
    return YES;
}


- (void) blipConnectionDidOpen:(BLIPConnection *)connection {
    NSString* name = ((BLIPPocketSocketConnection*)connection).webSocket.URLRequest.URL.path;
    name = name.stringByDeletingLastPathComponent.lastPathComponent;
    LogTo(Listener, @"OPENED INCOMING %@ from <%@> for %@", connection, connection.URL, name);

    [_manager.backgroundServer waitForDatabaseNamed: name to: ^id(CBLDatabase* db) {
        NSString* name = $sprintf(@"Sync from %@", connection.URL);
        dispatch_queue_t queue = dispatch_queue_create(name.UTF8String, DISPATCH_QUEUE_SERIAL);
        CBLSyncConnection* handler = [[CBLSyncConnection alloc] initWithDatabase: db
                                                                      connection: connection
                                                                           queue: queue];
        if (_facade.readOnly) {
            handler.onSyncAccessCheck = ^CBLStatus(BLIPRequest* request) {
                NSString* profile = request.profile;
                if ([profile isEqualToString:@"changes"] || [profile isEqualToString:@"rev"])
                    return kCBLStatusForbidden;
                return kCBLStatusOK;
            };
        }
        [handler addObserver: self forKeyPath: @"state" options: 0 context: (void*)1];
        dispatch_sync(_queue, ^{
            [_handlers addObject: handler];
            _facade.connectionCount = _handlers.count;
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
            LogTo(Listener, @"CLOSED INCOMING connection from <%@>", handler.peerURL);
            dispatch_sync(_queue, ^{
                [_handlers removeObject: handler];
                [handler removeObserver: self forKeyPath: @"state"];
                _facade.connectionCount = _handlers.count;
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


- (NSDictionary*) TXTRecordDictionary {
    return _txtData ? [NSNetService dictionaryFromTXTRecordData: _txtData] : nil;
}


- (void)setTXTRecordDictionary:(NSDictionary *)dict {
    NSData* txtData = dict ? [NSNetService dataFromTXTRecordDictionary: dict] : nil;
    dispatch_async(_queue, ^{
        _txtData = txtData;
        NSNetService* ns = _netService;
        if (ns) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ns.TXTRecordData = txtData;
            });
        }
    });
}


- (void) listenerDidStart {
    _facade.port = self.port;
    if (_bonjourType) {
        dispatch_async(_queue, ^{
            NSNetService* ns = [[NSNetService alloc] initWithDomain: @""
                                                               type: _bonjourType
                                                               name: _bonjourName
                                                               port: self.port];
            // Set ns.includesPeerToPeer = YES but only if it's supported (OS X 10.10, iOS 7)
            // and without getting a false positive warning from DeployMate:
            if ([ns respondsToSelector: @selector(setIncludesPeerToPeer:)])
                [ns setValue: @YES forKey: @"includesPeerToPeer"];
            ns.delegate = self;
            ns.TXTRecordData = _txtData;
            _netService = ns;
            dispatch_async(dispatch_get_main_queue(), ^{
                [ns publishWithOptions: 0];
            });
        });
    }
}


- (void) listenerDidStop {
    dispatch_async(_queue, ^{
        CBLSyncListener* facade = _facade;
        facade.port = 0;
        NSNetService* ns = _netService;
        if (ns) {
            _netService = nil;
            facade.bonjourName = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                ns.delegate = nil;
                [ns stop];
            });
        }
    });
}


// called on main thread
- (void)netServiceDidPublish:(NSNetService *)ns {
    NSString* name = ns.name;
    LogTo(Listener, @"CBLSyncListener: Published Bonjour service '%@'", name);
    _facade.bonjourName = name;
}


// called on main thread
- (void)netService:(NSNetService *)ns didNotPublish:(NSDictionary *)errorDict {
    Warn(@"CBLSyncListener: Failed to publish Bonjour service '%@': %@", ns.name, errorDict);
}

@end




@implementation CBLSyncListener
{
    CBLSyncListenerImpl* _impl;
    uint16_t _desiredPort;
}

@synthesize port=_port, connectionCount=_connectionCount;
@synthesize bonjourName=_bonjourName;


- (instancetype) initWithManager: (CBLManager*)manager port: (uint16_t)port {
    self = [super initWithManager: manager port: port];
    if (self) {
        _impl = [[CBLSyncListenerImpl alloc] initWithManager: manager facade: self];
        _desiredPort = port;
    }
    return self;
}

- (void) setBonjourName: (NSString*)name type: (NSString*)type {
    [_impl setBonjourName: name type: type];
}

- (NSDictionary*) TXTRecordDictionary                   {return _impl.TXTRecordDictionary;}
- (void)setTXTRecordDictionary:(NSDictionary *)dict     {_impl.TXTRecordDictionary = dict;}
- (void) setPasswords:(NSDictionary *)passwords         {_impl.passwords = passwords;}

- (BOOL) start: (NSError**)outError {
    return [_impl acceptOnInterface: nil
                               port: _desiredPort
                    SSLCertificates: self.SSLIdentityAndCertificates
                              error: outError];
}

- (void) stop {
    [_impl disconnect];
}


@end