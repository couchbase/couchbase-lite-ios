//
//  CBLWordEmbeddingModel.h
//  CBL_EE_ObjC
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
//  COUCHBASE CONFIDENTIAL -- part of Couchbase Lite Enterprise Edition
//

#import "CouchbaseLite.h"
#import "CBLPrediction.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLWordEmbeddingModel : NSObject <CBLPredictiveModel>

- (instancetype) initWithDatabase: (CBLDatabase*) database;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
