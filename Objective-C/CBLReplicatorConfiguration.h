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

NS_ASSUME_NONNULL_BEGIN

/** Replicator type. */
typedef enum {
    kCBLPushAndPull = 0,    ///< Bidirectional; both push and pull
    kCBLPush,               ///< Pushing changes to the target
    kCBLPull                ///< Pulling changes from the target
} CBLReplicatorType;


/** Replicator configuration. */
@interface CBLReplicatorConfiguration : NSObject <NSCopying>

/** The local database to replicate with the target database. */
@property (nonatomic, readonly, nullable) CBLDatabase* database;

/** 
 The replication target to replicate with. The replication target can be either a URL to
 the remote database or a local databaes.
 */
@property (nonatomic, readonly, nullable) id target;

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
 The conflict resolver for this replicator.
 The default value is nil, which means the local database's conflict resolver will be used.
 */
@property (nonatomic, nullable) id <CBLConflictResolver> conflictResolver;

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
 Allows the replicator to run when the app goes into the background.
 The default value is NO which means that the replicator will suspend itself when the app
 goes into the background, and will automatically resume when the app is brought into
 the foreground. The replicator will also resume when the -start method is called; this
 allows the replicator to be started or run when the app is already in the background.
 The replicator will suspend itself or stop (for a non-continuous replicator) when the
 replicator is inactive or the background task is expired.
 
 If the runInBackground property is set to YES, the replicator
 will allow to continue running in the background without suspension; it is the
 app's responsibility to manage the replicator running status when the app enters into the
 background, and comes back to the foreground.
 */
@property (nonatomic) BOOL runInBackground;
#endif

/**
  Creates a CBLReplicatorConfiguration with the given local database and remote database URL.
 */
+ (instancetype) withDatabase: (CBLDatabase*)database targetURL: (NSURL*)targetURL;

/** 
 Creates a CBLReplicatorConfiguration with the given local database and another local database.
 */
+ (instancetype) withDatabase: (CBLDatabase*)database targetDatabase: (CBLDatabase*)targetDatabase;

/** 
 Initializes a CBLReplicatorConfiguration with the given local database and remote database URL.
 */
- (instancetype) initWithDatabase: (CBLDatabase*)database targetURL: (NSURL*)targetURL;

/** 
 Initializes a CBLReplicatorConfiguration with the given local database and another local database.
 */
- (instancetype) initWithDatabase: (CBLDatabase*)database targetDatabase: (CBLDatabase*)targetDatabase;

@end


NS_ASSUME_NONNULL_END
