//
//  CBLReplicatorConfiguration.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplicatorConfiguration.h"
#import "CBLAuthenticator+Internal.h"
#import "CBLReplicator+Internal.h"
#import "CBLDatabase.h"


@implementation CBLReplicatorConfiguration

@synthesize database=_database, target=_target;
@synthesize replicatorType=_replicatorType, continuous=_continuous;
@synthesize conflictResolver=_conflictResolver;
@synthesize pinnedServerCertificate=_pinnedServerCertificate;
@synthesize authenticator=_authenticator, documentIDs=_documentIDs, channels=_channels;


+ (instancetype) withDatabase: (CBLDatabase*)database targetURL: (NSURL*)targetURL {
    return [[self alloc] initWithDatabase: database targetURL: targetURL];
}


+ (instancetype) withDatabase: (CBLDatabase*)database targetDatabase: (CBLDatabase*)targetDatabase {
    return [[self alloc] initWithDatabase: database targetDatabase: targetDatabase];
}


- (instancetype) initWithDatabase:(CBLDatabase *)database targetURL: (NSURL*)targetURL {
    self = [super init];
    if (self) {
        _replicatorType = kCBLPushAndPull;
        _database = database;
        _target = targetURL;
    }
    return self;
}


- (instancetype) initWithDatabase:(CBLDatabase *)database targetDatabase: (CBLDatabase*)targetDatabase {
    self = [super init];
    if (self) {
        _replicatorType = kCBLPushAndPull;
        _database = database;
        _target = targetDatabase;
    }
    return self;
}


- (instancetype) copyWithZone:(NSZone *)zone {
    CBLReplicatorConfiguration* c = [_target isKindOfClass: [NSURL class]] ?
        [[self.class alloc] initWithDatabase: _database targetURL: _target] :
        [[self.class alloc] initWithDatabase: _database targetDatabase: _target];
    c.replicatorType = _replicatorType;
    c.conflictResolver = _conflictResolver;
    c.continuous = _continuous;
    c.pinnedServerCertificate = _pinnedServerCertificate;
    c.authenticator = _authenticator;
    c.documentIDs = _documentIDs;
    c.channels = _channels;
    return c;
}


- (NSDictionary*) effectiveOptions {
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    
    NSURL* targetURL = $castIf(NSURL, _target);
    
    // If the URL has a hardcoded username/password, add them as an "auth" option:
    NSString* username = targetURL.user;
    if (username) {
        NSMutableDictionary *auth = [NSMutableDictionary new];
        auth[@kC4ReplicatorAuthUserName] = username;
        auth[@kC4ReplicatorAuthPassword] = targetURL.password;
        options[@kC4ReplicatorOptionAuthentication] = auth;
    } else
        [_authenticator authenticate: options];
    
    // Add the pinned certificate if any:
    if (_pinnedServerCertificate) {
        NSData* certData = CFBridgingRelease(SecCertificateCopyData(_pinnedServerCertificate));
        options[@kC4ReplicatorOptionPinnedServerCert] = certData;
    }

    options[@kC4ReplicatorOptionDocIDs] = _documentIDs;
    options[@kC4ReplicatorOptionChannels] = _channels;

    return options;
}


@end
