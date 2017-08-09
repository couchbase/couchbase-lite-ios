//
//  CBLCollationExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQuery+Internal.h"
@class CBLQueryCollation;

NS_ASSUME_NONNULL_BEGIN

@interface CBLCollationExpression : CBLQueryExpression

- (instancetype) initWithOperand: (CBLQueryExpression*)operand
                       collation: (CBLQueryCollation*)collation;

@end

NS_ASSUME_NONNULL_END
