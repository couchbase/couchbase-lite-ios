//
//  CBLReplicatorConfiguration.h
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

#import <Foundation/Foundation.h>
#import <Security/SecCertificate.h>
#import "CBLDocumentFlags.h"
#import "CBLReplicatorTypes.h"

@class CBLAuthenticator;
@class CBLCollection;
@class CBLCollectionConfiguration;
@class CBLDatabase;
@class CBLDocument;
@protocol CBLConflictResolver;
@protocol CBLEndpoint;

NS_ASSUME_NONNULL_BEGIN

/** Replicator Configuration */
@interface CBLReplicatorConfiguration: NSObject

/** The local database to replicate with the target endpoint. */
@property (nonatomic, readonly) CBLDatabase* database;

/**
 The replication endpoint to replicate with.
 */
@property (nonatomic, readonly) id<CBLEndpoint> target;

/**
 Replication type indicating the direction of the replication. The default value is
 .pushAndPull which is bidrectional.
 */
@property (nonatomic) CBLReplicatorType replicatorType;

/**
 Should the replicator stay active indefinitely, and push/pull changed documents?. The
 default value is NO.
 */
@property (nonatomic) BOOL continuous;

/**
 An Authenticator to authenticate with a remote server. Currently there are two types of
 the authenticators, CBLBasicAuthenticator and CBLSessionAuthenticator, supported.
 */
@property (nonatomic, nullable) CBLAuthenticator* authenticator;

/**
 If this property is non-null, the server is required to have this exact SSL/TLS certificate,
 or the connection will fail.
 */
@property (nonatomic, nullable) SecCertificateRef pinnedServerCertificate;

/**
 Extra HTTP headers to send in all requests to the remote target.
 */
@property (nonatomic, nullable) NSDictionary<NSString*, NSString*>* headers;

/*
 Specific network interface (e.g. en0 and pdp_ip0) for connecting to the remote target.
 */
@property (nonatomic, nullable) NSString* networkInterface;

/**
 Channels filter when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) NSArray<NSString*>* channels
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CollectionConfiguration object instead");

/**
 documentIDs filter when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) NSArray<NSString*>* documentIDs
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CollectionConfiguration object instead");

/**
 Push filter when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) CBLReplicationFilter pushFilter
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CollectionConfiguration object instead");

/**
 Pull filter when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) CBLReplicationFilter pullFilter
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CollectionConfiguration object instead");

/**
 Conflict resolver when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) id<CBLConflictResolver> conflictResolver
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CollectionConfiguration object instead");

#if TARGET_OS_IPHONE
/**
 Allows the replicator to continue replicating in the background. The default
 value is NO, which means that the replicator will suspend itself when the
 replicator detects that the application is being backgrounded.
 
 If setting the value to YES, please ensure that your application delegate
 requests background time from the OS until the replication finishes.
 */
@property (nonatomic) BOOL allowReplicatingInBackground;
#endif

/**
 The heartbeat interval in second.

 The interval when the replicator sends the ping message to check whether the other peer is still alive. Set the value to zero(by default)
 means using the default heartbeat of 300 seconds.
 
 Note: Setting the heartbeat to negative value will result in InvalidArgumentException being thrown.
 */
@property (nonatomic) NSTimeInterval heartbeat;

/**
 The maximum attempts to perform retry. The retry attempt will be reset when the replicator is able to connect and replicate with
 the remote server again.
 
 Setting the maxAttempts to zero(by default), the default maxAttempts of 10 times for single shot replicators and max-int times for
 continuous replicators will be applied and present to users. Settings the value to 1, will perform an initial request and
 if there is a transient error occurs, will stop without retry.
 */
@property (nonatomic) NSUInteger maxAttempts;

/**
 Max wait time for the next attempt(retry).
 
 The exponential backoff for calculating the wait time will be used by default and cannot be customized. Set the value to zero(by default)
 means using the default max attempts of 300 seconds.
 
 Set the maxAttemptWaitTime to negative value will result in InvalidArgumentException being thrown.
 */
@property (nonatomic) NSTimeInterval maxAttemptWaitTime;

/**
 To enable/disable the auto purge feature
 
 The default value is true which means that the document will be automatically purged by the
 pull replicator when the user loses access to the document from both removed and revoked scenarios.
 
 When the property is set to false, this behavior is disabled and an access removed event
 will be sent to any document listeners that are active on the replicator. For performance
 reasons, the document listeners must be added *before* the replicator is started or
 they will not receive the events.
 */
@property (nonatomic) BOOL enableAutoPurge;

/**
 The dictionary containing the collections and configurations used for replication.
 The dictionary contains the collections and the configurations added via
 the addCollection(_ collection:,config:) or addCollections(_ collections:,config:).
 Modifying the entries in the dictionary will reflect the collections and
 configured used for the replication. */
@property (nonatomic) NSDictionary<CBLCollection*, CBLCollectionConfiguration*>* collections;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

/**
 Initializes a CBLReplicatorConfiguration with the local database and
 the target endpoint.
 
 @param database The database.
 @param target The target endpoint.
 @return The CBLReplicatorConfiguration object.
 */
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           target: (id <CBLEndpoint>)target
__deprecated_msg("Use [... initWithTarget:] instead.");

/**
 Create a ReplicatorConfiguration object with the target’s endpoint.
 After the ReplicatorConfiguration object is created, use addCollection(_ collection:, config:)
 or addCollections(_ collections:, config:) to specify and configure the collections used for
 replicating with the target. If there are no collections specified, the replicator will fail
 to start with a no collections specified error.
 
 @param target The target endpoint.
 @return The CBLReplicatorConfiguration object.
 */
- (instancetype) initWithTarget: (id <CBLEndpoint>)target;

/**
 Initializes a CBLReplicatorConfiguration with the configuration object.
 
 @param config The configuration.
 @return The CBLReplicatorConfiguration object.
 */
- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config;

/**
 Add a collection used for the replication with an optional collection configuration.
 If the collection has been added before, the previous added and its configuration if specified
 will be replaced.
 If a null configuration is specified, a default empty configuration will be applied.
 
 @param collection The collection to be added.
 @param config Respective configuration for the collection, if nil, default config */
- (void) addCollection: (CBLCollection*)collection
                config: (nullable CBLCollectionConfiguration*)config;

/**
 Add multiple collections used for the replication with an optional shared collection configuration.
 If any of the collections have been added before, the previously added collections and their
 configuration if specified will be replaced. Adding an empty collection array will be no-ops. if
 specified will be replaced.
 
 If a null configuration is specified, a default empty configuration will be applied.
    
 @param collections The collections to be added.
 @param config Respective configuration for the collections, if nil, default config */
- (void) addCollections: (NSArray*)collections
                 config: (nullable CBLCollectionConfiguration*)config;

@end

NS_ASSUME_NONNULL_END
