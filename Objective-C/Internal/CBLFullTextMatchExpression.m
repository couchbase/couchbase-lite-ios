//
//  CBLFullTextMatchExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFullTextMatchExpression.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLFullTextMatchExpression {
    NSString* _indexName;
    NSString* _text;
}

- (instancetype) initWithIndexName: (NSString*)indexName text: (NSString*)text
{
    self = [super initWithNone];
    if (self) {
        _indexName = indexName;
        _text = text;
    }
    return self;
}


- (id) asJSON {
    return @[@"MATCH", _indexName, _text];
}

@end
