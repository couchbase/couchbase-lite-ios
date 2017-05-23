//
//  CBLDatabaseChange.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDatabaseChange.h"
#import "CBLInternal.h"

@implementation CBLDatabaseChange

@synthesize documentIDs=_documentIDs, isExternal=_isExternal;

- (instancetype) initWithDocumentIDs: (NSArray *)documentIDs isExternal: (BOOL)isExternal {
    self = [super init];
    if (self) {
        _documentIDs = documentIDs;
        _isExternal = isExternal;
    }
    return self;
}

@end
