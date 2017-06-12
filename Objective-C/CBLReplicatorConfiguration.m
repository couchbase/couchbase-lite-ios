//
//  CBLReplicatorConfiguration.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplicatorConfiguration.h"
#import "CBLReplicator+Internal.h"
#import "CBLDatabase.h"

NSString* const kCBLReplicatorAuthOption           = @"" kC4ReplicatorOptionAuthentication;
NSString* const kCBLReplicatorAuthUserName         = @"" kC4ReplicatorAuthUserName;
NSString* const kCBLReplicatorAuthPassword         = @"" kC4ReplicatorAuthPassword;


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
@synthesize options=_options;
@synthesize conflictResolver=_conflictResolver;
@synthesize pinnedServerCertificate=_pinnedServerCertificate;
@synthesize cookies=_cookies;


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
    c.options = _options;
    c.conflictResolver = _conflictResolver;
    c.continuous = _continuous;
    c.pinnedServerCertificate = _pinnedServerCertificate;
    c.cookies = _cookies;
    return c;
}


- (NSDictionary*) effectiveOptions {
    // If the URL has a hardcoded username/password, add them as an "auth" option:
    NSMutableDictionary* options = _options.mutableCopy ?: [NSMutableDictionary dictionary];
    NSString* username = _target.url.user;
    if (username && !options[kCBLReplicatorAuthOption]) {
        NSMutableDictionary *auth = [NSMutableDictionary new];
        auth[kCBLReplicatorAuthUserName] = username;
        auth[kCBLReplicatorAuthPassword] = _target.url.password;
        options[kCBLReplicatorAuthOption] = auth;
    }
    // Add the pinned certificate if any:
    if (_pinnedServerCertificate) {
        NSData* certData = CFBridgingRelease(SecCertificateCopyData(_pinnedServerCertificate));
        options[@kC4ReplicatorOptionPinnedServerCert] = certData;
    }
    // Add custom cookies if any:
    if (_cookies.count > 0) {
        NSMutableString *cookieStr = [NSMutableString new];
        for (NSHTTPCookie* cookie in _cookies) {
            if (cookieStr.length > 0)
                [cookieStr appendString: @"; "];
            Assert([cookie isKindOfClass: [NSHTTPCookie class]]);
            [cookieStr appendFormat: @"%@=%@", cookie.name, cookie.value];
        }
        options[@kC4ReplicatorOptionCookies] = cookieStr;
    }
    return options;
}


@end
