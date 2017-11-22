//
//  CBLQueryExpression+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//
#import "CBLQueryExpression.h"
#import "CBLQueryJSONEncoding.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryExpression () <CBLQueryJSONEncoding>

/** This constructor is for hiding the public -init: */
- (instancetype) initWithNone;

- (id) jsonValue: (id)value;

@end

NS_ASSUME_NONNULL_END
