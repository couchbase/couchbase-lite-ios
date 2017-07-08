//
//  CBLQueryMeta.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryMeta.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryMeta {
    NSString* _alias;
}


- (CBLQueryExpression*) documentID {
    return [CBLQueryExpression property: @"_id" from: _alias];
}


- (CBLQueryExpression*) sequence {
    return [CBLQueryExpression property: @"_sequence" from: _alias];
}


#pragma mark - Internal


- (instancetype) initWithFrom: (nullable NSString*)alias {
    self = [super init];
    if (self) {
        _alias = alias;
    }
    return self;
}


@end
