//
//  CBLIndexConfiguration+Internal.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/8/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLIndexConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLIndexConfiguration ()

- (instancetype) initWithIndexType: (C4IndexType)type expression: (NSString*)expression;

@end

NS_ASSUME_NONNULL_BEGIN

