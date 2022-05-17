//
//  CBLScope.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 5/17/22.
//  Copyright © 2022 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLCollection.h"

NS_ASSUME_NONNULL_BEGIN

@protocol CBLScope <NSObject>

#pragma mark Properties

/** Scope name. */
@property (readonly, nonatomic) NSString* name;

#pragma mark Collections

/** Get all collections in the scope. */
- (NSArray<CBLCollection*>*) getCollections;

/**
 Get a collection in the scope by name.
 If the collection doesn't exist, a nil value will be returned. */
- (CBLCollection*) getCollectionWithName: (NSString*)name;

@end

@interface CBLScope : NSObject<CBLScope>

@end

NS_ASSUME_NONNULL_END
