//
//  CBLQueryFTS.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryFTS.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryFTS


- (CBLQueryExpression*) rank: (NSString*)property {
    return [self rank: property from: nil];
}


- (CBLQueryExpression*) rank: (NSString*)property from:(nullable NSString *)alias {
    CBLQueryExpression* propExpr = [CBLQueryExpression property: property from: alias];
    return [[CBLQueryFunction alloc] initWithFunction: @"RANK()" params: @[propExpr]];
}


@end
