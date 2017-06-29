//
//  CBLDocumentChangeListener.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDocumentChangeListener.h"

@implementation CBLDocumentChangeListener

@synthesize documentID=_documentID;

- (instancetype) initWithDocumentID: (NSString*)documentID
                          withBlock: (id)block
{
    self = [super initWithBlock:block];
    if (self) {
        _documentID = documentID;
    }
    return self;
}

@end
