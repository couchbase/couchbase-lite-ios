//
//  CBLArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArray.h"
@class CBLSubdocument;
@class CBLArray;

NS_ASSUME_NONNULL_BEGIN

@protocol CBLArray <CBLReadOnlyArray>

- (void) setObject: (nullable id)object atIndex: (NSUInteger)index;

- (void) addObject: (nullable id)object;

- (void) insertObject: (nullable id)object atIndex: (NSUInteger)index;

- (void) removeObjectAtIndex: (NSUInteger)index;

- (nullable CBLSubdocument*) subdocumentAtIndex: (NSUInteger)index;

- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index;

- (void) setArray: (NSArray*)array;

@end

@interface CBLArray : CBLReadOnlyArray <CBLArray>

+ (instancetype) array;

- (instancetype) init;

@end

NS_ASSUME_NONNULL_END
