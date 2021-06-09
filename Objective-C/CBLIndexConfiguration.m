//
//  CBLIndexConfiguration.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/7/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLIndexConfiguration.h"
#import "CBLBaseIndex+Internal.h"

@implementation CBLIndexConfiguration {
    NSString* _expressions;
}

- (instancetype) initWithIndexType: (C4IndexType)type expression: (NSString*)expression {
    self = [super initWithIndexType: type queryLanguage: kC4N1QLQuery];
    if (self) {
        _expressions = expression;
    }
    return self;
}

- (NSString*) getIndexSpecs {
    return _expressions;
}

@end

@implementation CBLFullTextIndexConfiguration

- (instancetype) initWithExpression: (NSString*)expression {
    return [super initWithIndexType: kC4FullTextIndex expression: expression];
}

@end

@implementation CBLValueIndexConfiguration

- (instancetype) initWithExpression: (NSString*)expression {
    return [super initWithIndexType: kC4ValueIndex expression: expression];
}

@end

