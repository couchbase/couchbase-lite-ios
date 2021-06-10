//
//  CBLValueIndexConfiguration.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/9/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLValueIndexConfiguration.h"
#import "CBLIndexConfiguration+Internal.h"

@implementation CBLValueIndexConfiguration

- (instancetype) initWithExpression: (NSString*)expression {
    return [super initWithIndexType: kC4ValueIndex expression: expression];
}

@end
