//
//  CBLSyncListener.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/3/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLManager;


/** Listener/server for new replication protocol. */
@interface CBLSyncListener : NSObject

- (instancetype) initWithManager: (CBLManager*)manager
                            port: (uint16_t)port;

- (void) setBonjourName: (NSString*)name
                   type: (NSString*)type;

/** The published Bonjour service name. Nil until the server has started. Usually this is the same
    as the name you specified in -setBonjourName:type:, but if there's
    already a service with the same name on the network, your name may have a suffix appended. */
@property (readonly, copy) NSString* bonjourName;

/** Bonjour metadata associated with the service. Changes will be visible almost immediately.
    The keys are NSStrings and values are NSData. Total size should be kept small (under 1kbyte if possible) as this data is multicast over UDP. */
@property (copy, nonatomic) NSDictionary* TXTRecordDictionary;

- (void) setPasswords: (NSDictionary*)dict;

@property (copy) NSArray* SSLCertificates;

/** The URL at which the listener can be reached from another computer/device.
    This URL will only work for _local_ clients, i.e. over the same WiFi LAN or over Bluetooth.
    Allowing remote clients to connect is a difficult task that involves traversing routers or
    firewalls and translating local to global IP addresses, and it's generally impossible over
    cell networks because telcos don't allow incoming IP connections to mobile devices. */
@property (readonly) NSURL* URL;

/** The TCP port number that the listener is listening on. (Observable.)
    If the listener has not yet started, this will return 0. */
@property (readonly) UInt16 port;

/** The number of current client connections. (Observable.) */
@property (readonly) NSUInteger connectionCount;

- (BOOL) start: (NSError**)outError;
- (void) stop;

@end
