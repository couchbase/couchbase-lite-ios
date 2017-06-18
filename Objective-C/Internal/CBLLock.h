//
//  CBLLock.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLLock : NSObject <NSLocking>

@property (nonatomic, readonly, copy) NSString* name;

@property (nonatomic, readonly) BOOL recursive;

- (instancetype) initWithName: (NSString*)name;

- (instancetype) initWithName: (NSString*)name recursive: (BOOL)recursive;

- (void) withLock: (void(^)(void))block;

@end

NS_ASSUME_NONNULL_END
