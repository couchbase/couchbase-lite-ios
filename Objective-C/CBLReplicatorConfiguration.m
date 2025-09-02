//
//  CBLReplicatorConfiguration.m
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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
#import "CBLAuthenticator+Internal.h"
#import "CBLCollection+Internal.h"
#import "CBLCollectionConfiguration+Internal.h"
#import "CBLScope+Internal.h"
#import "CBLDefaults.h"
#import "CBLDatabase+Internal.h"
#import "CBLErrorMessage.h"
#import "CBLPrecondition.h"
#import "CBLReplicator+Internal.h"
#import "CBLVersion.h"

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
@synthesize acceptParentDomainCookies=_acceptParentDomainCookies;
@synthesize checkpointInterval=_checkpointInterval, heartbeat=_heartbeat;
@synthesize maxAttempts=_maxAttempts, maxAttemptWaitTime=_maxAttemptWaitTime;
@synthesize enableAutoPurge=_enableAutoPurge;
@synthesize collectionConfigMap=_collectionConfigMap;

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
        _acceptParentDomainCookies = kCBLDefaultReplicatorAcceptParentCookies;
        _heartbeat = kCBLDefaultReplicatorHeartbeat;
        _maxAttempts = kCBLDefaultReplicatorMaxAttemptsSingleShot;
        _maxAttemptWaitTime = kCBLDefaultReplicatorMaxAttemptsWaitTime;
        _enableAutoPurge = kCBLDefaultReplicatorEnableAutoPurge;
        _collectionConfigMap = [NSMutableDictionary dictionary];
    #if TARGET_OS_IPHONE
        _allowReplicatingInBackground = kCBLDefaultReplicatorAllowReplicatingInBackground;
    #endif
    }
    
    return self;
}

- (instancetype) initWithCollections: (NSArray<CBLCollectionConfiguration*>*)collections
                              target: (id <CBLEndpoint>)target {
    [CBLPrecondition assertArrayNotEmpty: collections name: @"collections"];
    [CBLPrecondition assertNotNil: target name: @"target"];
    
    self = [self initWithDefaults];
    if (self) {
        for (CBLCollectionConfiguration* config in collections) {
            [CBLPrecondition assert: config.collection != nil
                            message: @"Each collection configuration must have a non-null collection."];

            if (!_database) {
                _database = config.collection.database;
            } else {
                [CBLPrecondition assert: (self->_database == config.collection.database)
                                message: $sprintf(@"Collection '%@' belongs to a different database instance.",
                                                  config.collection.fullName)];
            }
            [_collectionConfigMap setObject: config forKey: config.collection];
        }
        _target = target;
    }
    return self;
}

- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config {
    CBLAssertNotNil(config);
    
    return [self initWithConfig: config readonly: NO];
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

- (void) setAcceptParentDomainCookies: (BOOL)acceptParentDomainCookies {
    [self checkReadonly];
    _acceptParentDomainCookies = acceptParentDomainCookies;
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
    if (![_collectionConfigMap allKeys].count){
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@", kCBLErrorMessageAccessDBWithoutCollection];
    }
    return _database;
}

- (NSArray<CBLCollectionConfiguration*>*) collectionConfigs {
    return [_collectionConfigMap allValues];
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
        _acceptParentDomainCookies = config.acceptParentDomainCookies;
        _headers = config.headers;
        _heartbeat = config.heartbeat;
        _checkpointInterval = config.checkpointInterval;
        _maxAttempts = config.maxAttempts;
        _maxAttemptWaitTime = config.maxAttemptWaitTime;
        _enableAutoPurge = config.enableAutoPurge;
#if TARGET_OS_IPHONE
        _allowReplicatingInBackground = config.allowReplicatingInBackground;
#endif
        _collectionConfigMap = [config.collectionConfigMap mutableCopy];
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
    
    // Accept Parent Domain Cookies:
    options[@kC4ReplicatorOptionAcceptParentDomainCookies] = @(_acceptParentDomainCookies);
    
    // Checkpoint intervals (no public api now):
    if (_checkpointInterval > 0)
        options[@kC4ReplicatorCheckpointInterval] = @(_checkpointInterval);
    
    options[@kC4ReplicatorHeartbeatInterval] = _heartbeat > 0
    ? @(_heartbeat)
    : @(kCBLDefaultReplicatorHeartbeat) /*backward compatibility*/;
    
    options[@kC4ReplicatorOptionMaxRetryInterval] = _maxAttemptWaitTime > 0
    ? @(_maxAttemptWaitTime)
    : @(kCBLDefaultReplicatorMaxAttemptsWaitTime) /*backward compatibility*/;
    
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
    [_collectionConfigMap removeAllObjects];
}

@end
