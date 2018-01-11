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

- (instancetype) initWithIndexName: (NSString*)name;

@end

@implementation CBLQueryFullTextExpression {
    NSString* _name;
}


- /* internal */ (instancetype) initWithIndexName: (NSString*)name {
    self = [super init];
    if (self) {
        _name = name;
    }
    return self;
}


+ (CBLQueryFullTextExpression*) indexWithName: (NSString*)name {
    return [[self alloc] initWithIndexName: name];
}


- (CBLQueryExpression*) match: (NSString*)text {
    return [[CBLFullTextMatchExpression alloc] initWithIndexName: _name
                                                            text: text];
}

@end
