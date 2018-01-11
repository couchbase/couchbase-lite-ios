//
//  CBLReplicatorConfiguration.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Security/SecCertificate.h>
@class CBLDatabase;
@class CBLAuthenticator;
@protocol CBLConflictResolver;
@protocol CBLEndpoint;

NS_ASSUME_NONNULL_BEGIN

/** Replicator type. */
typedef enum {
    kCBLReplicatorPushAndPull = 0,    ///< Bidirectional; both push and pull
    kCBLReplicatorPush,               ///< Pushing changes to the target
    kCBLReplicatorPull                ///< Pulling changes from the target
} CBLReplicatorType;


@interface CBLReplicatorConfigurationBuilder: NSObject

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
 The conflict resolver for this replicator. Setting nil means using the default
 conflict resolver, where the revision with more history wins.
 */
@property (nonatomic) id<CBLConflictResolver> conflictResolver;

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

/**
 A set of Sync Gateway channel names to pull from. Ignored for push replication.
 The default value is nil, meaning that all accessible channels will be pulled.
 Note: channels that are not accessible to the user will be ignored by Sync Gateway.
 */
@property (nonatomic, nullable) NSArray<NSString*>* channels;

/**
 A set of document IDs to filter by: if not nil, only documents with these IDs will be pushed
 and/or pulled.
 */
@property (nonatomic, nullable) NSArray<NSString*>* documentIDs;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end


/** Replicator configuration. */
@interface CBLReplicatorConfiguration : NSObject

/** The local database to replicate with the target database. */
@property (readonly, nonatomic) CBLDatabase* database;

/** 
 The replication target to replicate with. The replication target can be either a URL to
 the remote database or a local databaes.
 */
@property (readonly, nonatomic) id<CBLEndpoint> target;

/** 
 Replication type indicating the direction of the replication. The default value is
 .pushAndPull which is bidrectional.
 */
@property (readonly, nonatomic) CBLReplicatorType replicatorType;

/** 
 Should the replicator stay active indefinitely, and push/pull changed documents?. The
 default value is NO.
 */
@property (readonly, nonatomic) BOOL continuous;

/** 
 The conflict resolver for this replicator. Setting nil means using the default
 conflict resolver, where the revision with more history wins.
 */
@property (readonly, nonatomic) id<CBLConflictResolver> conflictResolver;

/**
 An Authenticator to authenticate with a remote server. Currently there are two types of
 the authenticators, CBLBasicAuthenticator and CBLSessionAuthenticator, supported.
 */
@property (readonly, nonatomic, nullable) CBLAuthenticator* authenticator;

/** 
 If this property is non-null, the server is required to have this exact SSL/TLS certificate,
 or the connection will fail.
 */
@property (readonly, nonatomic, nullable) SecCertificateRef pinnedServerCertificate;

/**
 Extra HTTP headers to send in all requests to the remote target.
 */
@property (readonly, nonatomic, nullable) NSDictionary<NSString*, NSString*>* headers;

/** 
 A set of Sync Gateway channel names to pull from. Ignored for push replication.
 The default value is nil, meaning that all accessible channels will be pulled.
 Note: channels that are not accessible to the user will be ignored by Sync Gateway.
 */
@property (readonly, nonatomic, nullable) NSArray<NSString*>* channels;

/** 
 A set of document IDs to filter by: if not nil, only documents with these IDs will be pushed
 and/or pulled.
 */
@property (readonly, nonatomic, nullable) NSArray<NSString*>* documentIDs;

/**
 Initializes a CBLReplicatorConfiguration with the given local database and
 the target endpoint.

 @param database The database.
 @param target The target endpoint.
 @return The CBLReplicatorConfiguration object.
 */
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           target: (id <CBLEndpoint>)target;

/**
 Initializes a CBLReplicatorConfiguration with the given local database,
 the target endpoint, and the configuration builder block.

 @param database The database.
 @param target The target endpoint.
 @param block The builder block.
 @return The CBLReplicatorConfiguration object.
 */
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           target: (id <CBLEndpoint>)target
                            block: (nullable void(^)(CBLReplicatorConfigurationBuilder* builder))block;

/**
 Initializes a CBLReplicatorConfiguration with the initialized configuration
 and the configuration builder block.
 
 @param config The configuration.
 @param block The builder block.
 @return The CBLReplicatorConfiguration object.
 */
- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config
                          block: (nullable void(^)(CBLReplicatorConfigurationBuilder* builder))block;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
