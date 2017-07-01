//
//  CBLQuerySelect.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuerySelect.h"
#import "CBLQuery+Internal.h"

@implementation CBLQuerySelect


@synthesize select=_select;


- (instancetype) initWithSelect: (id)select {
    self = [super init];
    if (self) {
        _select = select;
    }
    return self;
}


- (id) asJSON {
    if ([_select isKindOfClass: [CBLQueryExpression class]]) {
        CBLQueryExpression* exp = (CBLQueryExpression*)_select;
        return @[[exp asJSON]];
    } else if ([_select isKindOfClass: [NSArray class]]) {
        NSMutableArray* result = [NSMutableArray array];
        for (CBLQuerySelect* s in _select) {
            for (id subselect in [s asJSON])
                [result addObject: subselect];
        }
        return result;
    } else
        return @[];
}


+ (instancetype) all {
    return [[[self class] alloc] initWithSelect: nil];
}


+ (CBLQuerySelect*) expression: (CBLQueryExpression*)expression {
    return [[[self class] alloc] initWithSelect: expression];
}


+ (CBLQuerySelect*) select: (NSArray<CBLQuerySelect*>*)selects {
    return [[[self class] alloc] initWithSelect: selects];
}


@end
