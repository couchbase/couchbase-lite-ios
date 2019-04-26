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
#import "CBLAuthenticator+Internal.h"
#import "CBLReplicator+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CBLVersion.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLMessageEndpoint.h"
#endif

@implementation CBLReplicatorConfiguration {
    BOOL _readonly;
}

@synthesize database=_database, target=_target;
@synthesize replicatorType=_replicatorType, continuous=_continuous;
@synthesize authenticator=_authenticator;
@synthesize pinnedServerCertificate=_pinnedServerCertificate;
@synthesize headers=_headers;
@synthesize documentIDs=_documentIDs, channels=_channels;
@synthesize pushFilter=_pushFilter, pullFilter=_pullFilter;
@synthesize checkpointInterval=_checkpointInterval, heartbeatInterval=_heartbeatInterval;
@synthesize conflictResolver=_conflictResolver;

#if TARGET_OS_IPHONE
@synthesize allowReplicatingInBackground=_allowReplicatingInBackground;
#endif

- (instancetype) initWithDatabase: (CBLDatabase*)database
                           target: (id<CBLEndpoint>)target
{
    CBLAssertNotNil(database);
    CBLAssertNotNil(target);
    
    self = [super init];
    if (self) {
        _database = database;
        _target = target;
        _replicatorType = kCBLReplicatorTypePushAndPull;
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
}


- (void) setAuthenticator: (CBLAuthenticator *)authenticator {
    [self checkReadonly];
    _authenticator = authenticator;
}


- (void) setPinnedServerCertificate: (SecCertificateRef)pinnedServerCertificate {
    [self checkReadonly];
    if (_pinnedServerCertificate != pinnedServerCertificate) {
        cfrelease(_pinnedServerCertificate);
        _pinnedServerCertificate = pinnedServerCertificate;
        cfretain(_pinnedServerCertificate);
    }
}


- (void) setHeaders: (NSDictionary<NSString *,NSString *> *)headers {
    [self checkReadonly];
    _headers = headers;
}


- (void) setDocumentIDs: (NSArray<NSString *> *)documentIDs {
    [self checkReadonly];
    _documentIDs = documentIDs;
}


- (void) setChannels: (NSArray<NSString *> *)channels {
    [self checkReadonly];
    _channels = channels;
}


#if TARGET_OS_IPHONE
- (void) setAllowReplicatingInBackground: (BOOL)allowReplicatingInBackground {
    [self checkReadonly];
    _allowReplicatingInBackground = allowReplicatingInBackground;
}
#endif

#pragma mark - Internal


- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config
                       readonly: (BOOL)readonly {
    self = [super init];
    if (self) {
        _readonly = readonly;
        _database = config.database;
        _target = config.target;
        _replicatorType = config.replicatorType;
        _continuous = config.continuous;
        _authenticator = config.authenticator;
        _pinnedServerCertificate = config.pinnedServerCertificate;
        cfretain(_pinnedServerCertificate);
        _headers = config.headers;
        _documentIDs = config.documentIDs;
        _channels = config.channels;
        _pushFilter = config.pushFilter;
        _pullFilter = config.pullFilter;
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
    
    // Filters:
    options[@kC4ReplicatorOptionDocIDs] = _documentIDs;
    options[@kC4ReplicatorOptionChannels] = _channels;
    
    // Checkpoint & heartbeat intervals (no public api now):
    if (_checkpointInterval > 0)
        options[@kC4ReplicatorCheckpointInterval] = @(_checkpointInterval);
    if (_heartbeatInterval > 0)
        options[@kC4ReplicatorHeartbeatInterval] = @(_heartbeatInterval);
    
#ifdef COUCHBASE_ENTERPRISE
    NSString* uniqueID = $castIf(CBLMessageEndpoint, _target).uid;
    if (uniqueID)
        options[@kC4ReplicatorOptionRemoteDBUniqueID] = uniqueID;
#endif
    
    return options;
}


- (void) dealloc {
    cfrelease(_pinnedServerCertificate);
}


@end
