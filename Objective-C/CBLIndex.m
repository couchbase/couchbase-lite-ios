//
//  CBLIndex.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/30/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLIndex+Internal.h"

@implementation CBLIndex

- (instancetype) initWithNone {
    return [super init];
}

- (C4IndexType) indexType {
    // Implement by subclass
    return kC4ValueIndex;
}


- (C4IndexOptions) indexOptions {
    // Implement by subclass
    return (C4IndexOptions){ };
}


- (id) indexItems {
    return nil;
}

@end
