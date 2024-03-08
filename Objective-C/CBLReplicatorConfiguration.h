//
//  CBLReplicatorConfiguration.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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
#import <CouchbaseLite/CBLDocumentFlags.h>
#import <CouchbaseLite/CBLReplicatorTypes.h>

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

@property (nonatomic, readonly) CBLDatabase* database
__deprecated_msg(" Use config.collections instead");

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
 The remote target's SSL certificate.
 
 @Note: The pinned cert will be evaluated against any certs in a cert chain,
 and the cert chain will be valid only if the cert chain contains the pinned cert.
 */
@property (nonatomic, nullable) SecCertificateRef pinnedServerCertificate;

/**
 Extra HTTP headers to send in all requests to the remote target.
 */
@property (nonatomic, nullable) NSDictionary<NSString*, NSString*>* headers;

/**
 Specific network interface (e.g. en0 and pdp_ip0) for connecting to the remote target.
 */
@property (nonatomic, nullable) NSString* networkInterface;


/**
 The option to remove the restriction that does not allow the replicator to save the parent-domain
 cookies, the cookies whose domains are the parent domain of the remote host, from the HTTP
 response. For example, when the option is set to true, the cookies whose domain are “.foo.com”
 returned by “bar.foo.com” host will be permitted to save.
      
 This option is disabled by default (See ``kCBLDefaultReplicatorAcceptParentCookies``)
 which means that the parent-domain cookies are not permitted to save by default.
 */
@property (nonatomic) BOOL acceptParentDomainCookies;

/**
 Channels filter when using init(database:target:) to configure the default collection
 for the replication.
 
 @Note: Channels are not supported in Peer-to-Peer and Database-to-Database replication.
 */
@property (nonatomic, nullable) NSArray<NSString*>* channels
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CBLCollectionConfiguration object instead");

/**
 documentIDs filter when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) NSArray<NSString*>* documentIDs
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CBLCollectionConfiguration object instead");

/**
 Push filter when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) CBLReplicationFilter pushFilter
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CBLCollectionConfiguration object instead");

/**
 Pull filter when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) CBLReplicationFilter pullFilter
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CBLCollectionConfiguration object instead");

/**
 Conflict resolver when using init(database:target:) to configure the default collection
 for the replication.
 */
@property (nonatomic, nullable) id<CBLConflictResolver> conflictResolver
__deprecated_msg(" Use [... initWithTarget:] and [config addCollection: config:]" \
                 " with a CBLCollectionConfiguration object instead");

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

 The interval when the replicator sends the ping message to check whether the other peer is still alive.
 Default heartbeat is ``kCBLDefaultReplicatorHeartbeat`` seconds.
 
 @Note:
 Setting the heartbeat to negative value will result in InvalidArgumentException being thrown.
 For backward compatibility, setting to zero will result in default heartbeat internally.
 */
@property (nonatomic) NSTimeInterval heartbeat;

/**
 The maximum attempts to perform retry. The retry attempt will be reset when the replicator is
 able to connect and replicate with the remote server again.
 
 Default maxAttempts is ``kCBLDefaultReplicatorMaxAttemptsSingleShot`` times
 for single shot replicators and ``kCBLDefaultReplicatorMaxAttemptsContinuous`` times
 for continuous replicators.
 
 Settings the value to 1, will perform an initial request and
 if there is a transient error occurs, will stop without retry.
 
 @Note: For backward compatibility, setting it to zero will result in default maxAttempt internally.
 */
@property (nonatomic) NSUInteger maxAttempts;

/**
 Max wait time for the next attempt(retry).
 
 The exponential backoff for calculating the wait time will be used by default and cannot be customized.
 Default max attempts is ``kCBLDefaultReplicatorMaxAttemptsWaitTime`` seconds.
 
 @Note: Set the maxAttemptWaitTime to negative value will result in InvalidArgumentException being thrown.
 For backward compatibility, setting it to zero will result in default maxAttemptWaitTime internally.
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
 
 @Note: Auto purge will not be performed when documentIDs filter is specified.
 */
@property (nonatomic) BOOL enableAutoPurge;

/** The collections used for the replication. */
@property (nonatomic, readonly) NSArray<CBLCollection*>* collections;

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
 @param config Configuration for the collection, if nil, default config */
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

/**
 Remove the collection. If the collection doesn’t exist, this operation will be no ops.
 
 @param collection The collection to be removed. */
- (void) removeCollection: (CBLCollection*)collection;

/**
 Get a copy of the collection’s config. If the config needs to be changed for the collection, the
 collection will need to be re-added with the updated config.
 
 @param collection The collection whose config is needed.
 @return The collection configuration, or nil if config doesn't exist */
- (nullable CBLCollectionConfiguration*) collectionConfig: (CBLCollection*)collection;

@end

NS_ASSUME_NONNULL_END
