//
//  CBLDocumentChange.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDocumentChange.h"
#import "CBLInternal.h"

@implementation CBLDocumentChange

@synthesize documentID=_documentID;

- (instancetype) initWithDocumentID: (NSString *)documentID {
    self = [super init];
    if (self) {
        _documentID = documentID;
    }
    return self;
}

@end
