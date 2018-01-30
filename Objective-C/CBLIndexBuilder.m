//
//  CBLIndexBuilder.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/29/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLIndexBuilder.h"
#import "CBLIndex+Internal.h"

@implementation CBLIndexBuilder

+ (CBLValueIndex*) valueIndexWithItems: (NSArray<CBLValueIndexItem*>*)items {
    return [[CBLValueIndex alloc] initWithItems: items];
}


+ (CBLFullTextIndex*) fullTextIndexWithItems: (NSArray<CBLFullTextIndexItem*>*)items {
    return [[CBLFullTextIndex alloc] initWithItems: items];
}

@end
