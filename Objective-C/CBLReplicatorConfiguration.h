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
@class CBLDatabase;
@class CBLAuthenticator;
@protocol CBLEndpoint;

NS_ASSUME_NONNULL_BEGIN

/** Replicator type. */
typedef enum {
    kCBLReplicatorTypePushAndPull = 0,    ///< Bidirectional; both push and pull
    kCBLReplicatorTypePush,               ///< Pushing changes to the target
    kCBLReplicatorTypePull                ///< Pulling changes from the target
} CBLReplicatorType;


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
                           target: (id <CBLEndpoint>)target;

/**
 Initializes a CBLReplicatorConfiguration with the configuration object.
 
 @param config The configuration.
 @return The CBLReplicatorConfiguration object.
 */
- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config;

@end

NS_ASSUME_NONNULL_END
