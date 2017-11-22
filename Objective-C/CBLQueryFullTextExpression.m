//
//  CBLQueryFullTextExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryFullTextExpression.h"
#import "CBLFullTextMatchExpression.h"

@interface CBLQueryFullTextExpression ()

- (instancetype) initWithIndexName: (NSString*)indexName;

@end

@implementation CBLQueryFullTextExpression {
    NSString* _indexName;
}


- /* internal */ (instancetype) initWithIndexName: (NSString*)indexName {
    self = [super init];
    if (self) {
        _indexName = indexName;
    }
    return self;
}


+ (CBLQueryFullTextExpression*) index: (NSString*)indexName {
    return [[self alloc] initWithIndexName: indexName];
}


- (CBLQueryExpression*) match: (NSString*)text {
    return [[CBLFullTextMatchExpression alloc] initWithIndexName: _indexName
                                                            text: text];
}

@end
