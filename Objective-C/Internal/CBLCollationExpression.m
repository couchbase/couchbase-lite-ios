//
//  CBLCollationExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLCollationExpression.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryExpression+Internal.h"


@implementation CBLCollationExpression {
    CBLQueryExpression* _operand;
    CBLQueryCollation* _collation;
}

- (instancetype) initWithOperand: (CBLQueryExpression*)operand
                       collation: (CBLQueryCollation*)collation
{
    self = [super initWithNone];
    if (self) {
        _operand = operand;
        _collation = collation;
    }
    return self;
}


- (id) asJSON {
    return @[@"COLLATE", [_collation asJSON], [_operand asJSON]];
}


@end
