//
//  CBLReplicatorConfiguration.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplicatorConfiguration.h"
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
    return c;
}


@end
