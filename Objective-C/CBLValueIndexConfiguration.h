//
//  CBLValueIndexConfiguration.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/9/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLIndexConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLValueIndexConfiguration : CBLIndexConfiguration

- (instancetype) initWithExpression: (NSString*)expression;

@end

NS_ASSUME_NONNULL_END
