//
//  CBLSharedKeys.h
//  CouchbaseLite
//
//  Created by Callum Birks on 10/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CBLSharedKeys;

NS_ASSUME_NONNUL_BEGIN

@protocol CBLSharedKeys <NSObject, NSFastEnumeration>

@property (readonly) NSUInteger count;

- (nullable NSString*) decode: (NSInteger)key;

- (NSInteger) encode: (NSString*)str;

- (NSInteger) encodeAndAdd: (NSString*)str;

@end

@interface CBLSharedKeys : NSObject <CBLSharedKeys>

@end

NS_ASSUME_NONNULL_END
