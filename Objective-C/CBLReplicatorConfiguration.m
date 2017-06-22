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


@implementation CBLReplicatorTarget {
    id _target;
}


+ (instancetype) url: (NSURL*)url {
    return [[self alloc] initWithURL: url];
}


+ (instancetype) database: (CBLDatabase*)database {
    return [[self alloc] initWithDatabase: database];
}


- (instancetype) initWithURL:(NSURL *)url {
    return [self initWithTarget: url];
}


- (instancetype) initWithDatabase:(CBLDatabase *)database {
    return [self initWithTarget: database];
}


- /* private */ (instancetype) initWithTarget: (id)target {
    self = [super init];
    if (self) {
        _target = target;
    }
    return self;
}


- (CBLDatabase*) database {
    return $castIf(CBLDatabase, _target);
}


- (NSURL*) url {
    return $castIf(NSURL, _target);
}


- (NSString*) description {
    NSURL* remoteURL = self.url;
    if (remoteURL)
        return remoteURL.absoluteString;
    else
        return self.database.name;
}

@end


@implementation CBLReplicatorConfiguration

@synthesize database=_database, target=_target;
@synthesize replicatorType=_replicatorType, continuous=_continuous;
@synthesize conflictResolver=_conflictResolver;
@synthesize pinnedServerCertificate=_pinnedServerCertificate;
@synthesize authenticator=_authenticator;


- (instancetype) init {
    self = [super init];
    if (self) {
        _replicatorType = kCBLPushAndPull;
    }
    return self;
}


- (instancetype) copyWithZone:(NSZone *)zone {
    CBLReplicatorConfiguration* c = [[self.class alloc] init];
    c.database = _database;
    c.target = _target;
    c.replicatorType = _replicatorType;
    c.conflictResolver = _conflictResolver;
    c.continuous = _continuous;
    c.pinnedServerCertificate = _pinnedServerCertificate;
    c.authenticator = _authenticator;
    return c;
}


- (NSDictionary*) effectiveOptions {
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    
    // If the URL has a hardcoded username/password, add them as an "auth" option:
    NSString* username = _target.url.user;
    if (username) {
        NSMutableDictionary *auth = [NSMutableDictionary new];
        auth[@kC4ReplicatorAuthUserName] = username;
        auth[@kC4ReplicatorAuthPassword] = _target.url.password;
        options[@kC4ReplicatorOptionAuthentication] = auth;
    } else
        [_authenticator authenticate: options];
    
    // Add the pinned certificate if any:
    if (_pinnedServerCertificate) {
        NSData* certData = CFBridgingRelease(SecCertificateCopyData(_pinnedServerCertificate));
        options[@kC4ReplicatorOptionPinnedServerCert] = certData;
    }
    
    return options;
}


@end
