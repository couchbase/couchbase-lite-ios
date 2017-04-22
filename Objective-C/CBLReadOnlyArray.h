//
//  CBLReadOnlyArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArrayFragment.h"
@class CBLBlob;
@class CBLReadOnlySubdocument;
@class CBLReadOnlyArray;

NS_ASSUME_NONNULL_BEGIN

@protocol CBLReadOnlyArray <NSObject, CBLReadOnlyArrayFragment>

@property (readonly) NSUInteger count;

- (nullable id) objectAtIndex: (NSUInteger)index;

- (BOOL) booleanAtIndex: (NSUInteger)index;

- (NSInteger) integerAtIndex: (NSUInteger)index;

- (float) floatAtIndex: (NSUInteger)index;

- (double) doubleAtIndex: (NSUInteger)index;

- (nullable NSString*) stringAtIndex: (NSUInteger)index;

- (nullable NSNumber*) numberAtIndex: (NSUInteger)index;

- (nullable NSDate*) dateAtIndex: (NSUInteger)index;

- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index;

- (nullable CBLReadOnlySubdocument*) subdocumentAtIndex: (NSUInteger)index;

- (nullable CBLReadOnlyArray*) arrayAtIndex: (NSUInteger)index;

- (NSArray*) toArray;

@end

@interface CBLReadOnlyArray : NSObject <CBLReadOnlyArray>

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
