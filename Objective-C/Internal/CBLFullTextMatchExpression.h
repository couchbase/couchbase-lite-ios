//
//  CBLFullTextMatchExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLFullTextMatchExpression : CBLQueryExpression

- (instancetype) initWithIndexName: (NSString*)indexName text: (NSString*)text;

@end

NS_ASSUME_NONNULL_END
