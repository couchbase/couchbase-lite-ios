//
//  CBLReplicatorConfiguration.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLReplicatorConfiguration.h"
#import "CBLReplicatorConfiguration+Swift.h"
#import "CBLAuthenticator+Internal.h"
#import "CBLReplicator+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CBLErrorMessage.h"
#import "CBLVersion.h"
#import "CBLCollection+Internal.h"
#import "CBLCollectionConfiguration+Internal.h"
#import "CBLDefaults.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLMessageEndpoint.h"
#import "CBLReplicatorConfiguration+ServerCert.h"
#endif

@implementation CBLReplicatorConfiguration {
    BOOL _readonly;
    BOOL _isMaxAttemptUpdated;
}

@synthesize database=_database, target=_target;
@synthesize replicatorType=_replicatorType, continuous=_continuous;
@synthesize authenticator=_authenticator;
@synthesize pinnedServerCertificate=_pinnedServerCertificate;
@synthesize headers=_headers;
@synthesize networkInterface=_networkInterface;
@synthesize checkpointInterval=_checkpointInterval, heartbeat=_heartbeat;
@synthesize maxAttempts=_maxAttempts, maxAttemptWaitTime=_maxAttemptWaitTime;
@synthesize enableAutoPurge=_enableAutoPurge;
@synthesize collectionConfigs=_collectionConfigs;

#ifdef COUCHBASE_ENTERPRISE
@synthesize acceptOnlySelfSignedServerCertificate=_acceptOnlySelfSignedServerCertificate;
#endif

#if TARGET_OS_IPHONE
@synthesize allowReplicatingInBackground=_allowReplicatingInBackground;
#endif

- (instancetype) initWithDefaults {
    self = [super init];
    if (self) {
        _replicatorType = kCBLDefaultReplicatorType;
    #ifdef COUCHBASE_ENTERPRISE
        _acceptOnlySelfSignedServerCertificate = kCBLDefaultReplicatorSelfSignedCertificateOnly;
    #endif
        _continuous = kCBLDefaultReplicatorContinuous;
        _heartbeat = kCBLDefaultReplicatorHeartbeat;
        _maxAttempts = kCBLDefaultReplicatorMaxAttemptsSingleShot;
        _maxAttemptWaitTime = kCBLDefaultReplicatorMaxAttemptWaitTime;
        _enableAutoPurge = kCBLDefaultReplicatorEnableAutoPurge;
        _collectionConfigs = [NSMutableDictionary dictionary];
    #if TARGET_OS_IPHONE
        _allowReplicatingInBackground = kCBLDefaultReplicatorAllowReplicatingInBackground;
    #endif
    }
    
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                           target: (id<CBLEndpoint>)target
{
    CBLAssertNotNil(database);
    CBLAssertNotNil(target);
    
    self = [self initWithDefaults];
    if (self) {
        _database = database;
        _target = target;
        
        // add default collection
        CBLCollection* defaultCollection = [_database defaultCollectionOrThrow];
        CBLCollectionConfiguration* defaultCollectionConfig = [[CBLCollectionConfiguration alloc] init];
        [self addCollection: defaultCollection config: defaultCollectionConfig];
        
    }
    return self;
}

- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config {
    CBLAssertNotNil(config);
    
    return [self initWithConfig: config readonly: NO];
}

- (instancetype) initWithTarget:(id<CBLEndpoint>)target {
    CBLAssertNotNil(target);
    self = [self initWithDefaults];
    if (self) {
        _target = target;
    }
    return self;
}

- (void) setReplicatorType: (CBLReplicatorType)replicatorType {
    [self checkReadonly];
    _replicatorType = replicatorType;
}

- (void) setContinuous: (BOOL)continuous {
    [self checkReadonly];
    
    _continuous = continuous;
    
    if (!_isMaxAttemptUpdated)
        _maxAttempts = continuous
        ? kCBLDefaultReplicatorMaxAttemptsContinuous
        : kCBLDefaultReplicatorMaxAttemptsSingleShot;
}

- (void) setAuthenticator: (CBLAuthenticator*)authenticator {
    [self checkReadonly];
    _authenticator = authenticator;
}

#ifdef COUCHBASE_ENTERPRISE
- (void) setAcceptOnlySelfSignedServerCertificate: (BOOL)acceptOnlySelfSignedServerCertificate {
    [self checkReadonly];
    _acceptOnlySelfSignedServerCertificate = acceptOnlySelfSignedServerCertificate;
}
#endif

- (void) setPinnedServerCertificate: (SecCertificateRef)pinnedServerCertificate {
    [self checkReadonly];
    if (_pinnedServerCertificate != pinnedServerCertificate) {
        cfrelease(_pinnedServerCertificate);
        _pinnedServerCertificate = pinnedServerCertificate;
        cfretain(_pinnedServerCertificate);
    }
}

- (void) setHeaders: (NSDictionary<NSString *,NSString *>*)headers {
    [self checkReadonly];
    _headers = headers;
}

- (void) setNetworkInterface: (NSString*)networkInterface {
    [self checkReadonly];
    _networkInterface = networkInterface;
}

- (CBLCollectionConfiguration*) defaultCollectionConfig {
    CBLCollection* defaultCollection = [_database defaultCollectionOrThrow];
    return _collectionConfigs[defaultCollection];
}

- (CBLCollectionConfiguration*) defaultCollectionConfigOrThrow {
    CBLCollectionConfiguration* config = [self defaultCollectionConfig];
    if (!config) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@", kCBLErrorMessageNoDefaultCollectionInConfig];
    }
    return config;
}

- (void) setDocumentIDs: (NSArray<NSString *>*)documentIDs {
    [self checkReadonly];
    [self defaultCollectionConfigOrThrow].documentIDs = documentIDs;
}

- (NSArray<NSString*>*) documentIDs {
    return [self defaultCollectionConfig].documentIDs;
}

- (void) setChannels: (NSArray<NSString *>*)channels {
    [self checkReadonly];
    [self defaultCollectionConfigOrThrow].channels = channels;
}

- (NSArray<NSString*>*) channels {
    return [self defaultCollectionConfig].channels;
}

- (void) setConflictResolver: (id<CBLConflictResolver>)conflictResolver {
    [self checkReadonly];
    [self defaultCollectionConfigOrThrow].conflictResolver = conflictResolver;
}

- (id<CBLConflictResolver>) conflictResolver {
    return [self defaultCollectionConfig].conflictResolver;
}

- (void) setPullFilter: (CBLReplicationFilter)pullFilter {
    [self defaultCollectionConfigOrThrow].pullFilter = pullFilter;
}

- (CBLReplicationFilter) pullFilter {
    return [self defaultCollectionConfig].pullFilter;
}

- (void) setPushFilter: (CBLReplicationFilter)pushFilter {
    [self defaultCollectionConfigOrThrow].pushFilter = pushFilter;
}

- (CBLReplicationFilter) pushFilter {
    return [self defaultCollectionConfig].pushFilter;
}

#if TARGET_OS_IPHONE
- (void) setAllowReplicatingInBackground: (BOOL)allowReplicatingInBackground {
    [self checkReadonly];
    _allowReplicatingInBackground = allowReplicatingInBackground;
}
#endif

- (void) setHeartbeat: (NSTimeInterval)heartbeat {
    [self checkReadonly];
    
    if (heartbeat < 0)
        [NSException raise: NSInvalidArgumentException
                    format: @"%@", kCBLErrorMessageNegativeHeartBeat];
    
    _heartbeat = heartbeat;
}

- (void) setMaxAttempts: (NSUInteger)maxAttempts {
    [self checkReadonly];
    _isMaxAttemptUpdated = YES;
    _maxAttempts = maxAttempts;
}

- (void) setMaxAttemptWaitTime: (NSTimeInterval)maxAttemptWaitTime {
    [self checkReadonly];
    
    if (maxAttemptWaitTime < 0)
        [NSException raise: NSInvalidArgumentException
                    format: @"%@", kCBLErrorMessageNegativeMaxAttemptWaitTime];
    
    _maxAttemptWaitTime = maxAttemptWaitTime;
}

- (void) setEnableAutoPurge: (BOOL)enableAutoPurge {
    [self checkReadonly];
    _enableAutoPurge = enableAutoPurge;
}

- (CBLDatabase*) database {
    if (!_database)
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@", kCBLErrorMessageAccessDBWithoutCollection];
    return _database;
}

- (void) addCollection: (CBLCollection*)collection
                config: (nullable CBLCollectionConfiguration*)config {    
    CBLDatabase* colDB = collection.db;
    if (!collection.isValid || !colDB) {
        [NSException raise: NSInvalidArgumentException
                    format: @"%@", kCBLErrorMessageAddInvalidCollection];
    }
    
    if (_database) {
        if (_database != colDB) {
            [NSException raise: NSInvalidArgumentException
                        format: @"%@", kCBLErrorMessageAddCollectionFromAnotherDB];
        }
    } else {
        _database = colDB;
    }
    
    // collection config is copied
    CBLCollectionConfiguration* colConfig = nil;
    if (config)
        colConfig = [[CBLCollectionConfiguration alloc] initWithConfig: config];
    else
        colConfig = [[CBLCollectionConfiguration alloc] init];
    
    [_collectionConfigs setObject: colConfig forKey: collection];
}

- (void) addCollections: (NSArray<CBLCollection*>*)collections
                 config: (nullable CBLCollectionConfiguration*)config {
    if (collections.count <= 0) {
        [NSException raise: NSInvalidArgumentException
                    format: @"%@", kCBLErrorMessageAddEmptyCollectionArray];
    }
    
    for (CBLCollection* col in collections) {
        [self addCollection: col config: config];
    }
}

- (NSArray<CBLCollection*>*) collections {
    return _collectionConfigs.allKeys;
}

- (void) removeCollection:(CBLCollection *)collection {
    [_collectionConfigs removeObjectForKey: collection];
    
    // reset the database, when all collections are removed
    if (_collectionConfigs.count == 0) {
        _database = nil;
    }
}

- (CBLCollectionConfiguration*) collectionConfig:(CBLCollection *)collection {
    return [_collectionConfigs objectForKey: collection];
}

#pragma mark - Internal

- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config
                       readonly: (BOOL)readonly {
    self = [self initWithDefaults];
    if (self) {
        _database = config.database;
        _readonly = readonly;
        _target = config.target;
        _replicatorType = config.replicatorType;
        _continuous = config.continuous;
        _authenticator = config.authenticator;
#ifdef COUCHBASE_ENTERPRISE
        _acceptOnlySelfSignedServerCertificate = config.acceptOnlySelfSignedServerCertificate;
#endif
        _pinnedServerCertificate = config.pinnedServerCertificate;
        cfretain(_pinnedServerCertificate);
        _networkInterface = config.networkInterface;
        _headers = config.headers;
        _collectionConfigs = [NSMutableDictionary dictionaryWithCapacity: config.collectionConfigs.count];
        for (CBLCollection* col in config.collectionConfigs) {
            if (col.isValid) {
                [_collectionConfigs setObject: [config.collectionConfigs objectForKey: col] forKey: col];
            }
        }
        _heartbeat = config.heartbeat;
        _checkpointInterval = config.checkpointInterval;
        _maxAttempts = config.maxAttempts;
        _maxAttemptWaitTime = config.maxAttemptWaitTime;
        _enableAutoPurge = config.enableAutoPurge;
#if TARGET_OS_IPHONE
        _allowReplicatingInBackground = config.allowReplicatingInBackground;
#endif
    }
    return self;
}

- (void) checkReadonly {
    if (_readonly) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"This configuration object is readonly."];
    }
}

- (NSDictionary*) effectiveOptions {
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    
    // Add authentication info if any:
    [_authenticator authenticate: options];
    
    // Add the pinned certificate if any:
    if (_pinnedServerCertificate) {
        NSData* certData = CFBridgingRelease(SecCertificateCopyData(_pinnedServerCertificate));
        options[@kC4ReplicatorOptionPinnedServerCert] = certData;
    }
    
    // User-Agent and HTTP headers:
    NSMutableDictionary* httpHeaders = [NSMutableDictionary dictionary];
    httpHeaders[@"User-Agent"] = [CBLVersion userAgent];
    if (self.headers)
        [httpHeaders addEntriesFromDictionary: self.headers];
    options[@kC4ReplicatorOptionExtraHeaders] = httpHeaders;
    
    // TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    // Filters:
    options[@kC4ReplicatorOptionDocIDs] = self.documentIDs;
    options[@kC4ReplicatorOptionChannels] = self.channels;
    
#pragma clang diagnostic pop
    
    // Checkpoint intervals (no public api now):
    if (_checkpointInterval > 0)
        options[@kC4ReplicatorCheckpointInterval] = @(_checkpointInterval);
    
    options[@kC4ReplicatorHeartbeatInterval] = _heartbeat > 0
    ? @(_heartbeat)
    : @(kCBLDefaultReplicatorHeartbeat) /*backward compatibility*/;
    
    options[@kC4ReplicatorOptionMaxRetryInterval] = _maxAttemptWaitTime > 0
    ? @(_maxAttemptWaitTime)
    : @(kCBLDefaultReplicatorMaxAttemptWaitTime) /*backward compatibility*/;
    
    if (_maxAttempts > 0) {
        options[@kC4ReplicatorOptionMaxRetries] =  @(_maxAttempts - 1);
    } else {
        // backward compatibility support 0
        options[@kC4ReplicatorOptionMaxRetries] = _continuous ? @(kCBLDefaultReplicatorMaxAttemptsContinuous) : @(kCBLDefaultReplicatorMaxAttemptsSingleShot);
    }
    
    if (!_enableAutoPurge)
        options[@kC4ReplicatorOptionAutoPurge] = @(NO);
    
#ifdef COUCHBASE_ENTERPRISE
    NSString* uniqueID = $castIf(CBLMessageEndpoint, _target).uid;
    if (uniqueID)
        options[@kC4ReplicatorOptionRemoteDBUniqueID] = uniqueID;
    
    options[@kC4ReplicatorOptionOnlySelfSignedServerCert] = @(_acceptOnlySelfSignedServerCertificate);
#endif
    
    return options;
}

- (void) dealloc {
    cfrelease(_pinnedServerCertificate);
    [_collectionConfigs removeAllObjects];
}

@end
