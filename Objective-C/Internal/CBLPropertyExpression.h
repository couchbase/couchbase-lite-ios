//
//  CBLPropertyExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kCBLAllPropertiesName;

@interface CBLPropertyExpression : CBLQueryExpression

@property(nonatomic, readonly) NSString* keyPath;

@property(nonatomic, readonly) NSString* columnName;

@property(nonatomic, readonly, nullable) NSString* from; // Data Source Alias

- (instancetype) initWithKeyPath: (NSString*)keyPath
                      columnName: (nullable NSString*)columnName
                            from: (nullable NSString*)from;


+ (instancetype) allFrom: (nullable NSString*)from;

@end

NS_ASSUME_NONNULL_END
