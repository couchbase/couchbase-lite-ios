//
//  CBLFullTextIndexConfiguration.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/9/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLIndexConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLFullTextIndexConfiguration : CBLIndexConfiguration

@property (nonatomic) BOOL ignoreAccents;

@property (nonatomic, copy, nullable) NSString* language;

- (instancetype) initWithExpression: (NSString*)expression
                      ignoreAccents: (BOOL)ignoreAccents
                           language: (NSString* __nullable)language;

@end

NS_ASSUME_NONNULL_END
