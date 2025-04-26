//
//  CBLReplicationConflictResolver.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/5/25.
//  Copyright © 2025 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CBLCollection;
@class CBLReplicatedDocument;
@protocol CBLConflictResolver;

NS_ASSUME_NONNULL_BEGIN

@interface CBLConflictResolverService : NSObject

- (instancetype) initWithReplicatorID: (NSString*)replicatorID;

- (BOOL) shutdown: (void (^)(void))completion;

- (void) addConflict: (CBLReplicatedDocument*)doc
          collection: (CBLCollection*)collection
            resolver: (id<CBLConflictResolver>)resolver
          completion: (void (^)(BOOL cancelled, NSError* _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
