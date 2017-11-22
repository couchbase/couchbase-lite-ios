//
//  CBLDocumentChangeListenerToken.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDocumentChangeListenerToken.h"

@implementation CBLDocumentChangeListenerToken


@synthesize documentID=_documentID;

- (instancetype) initWithDocumentID: (NSString*)documentID
                           listener: (id)listener
                              queue: (dispatch_queue_t)queue
{
    self = [super initWithListener: listener queue: queue];
    if (self) {
        _documentID = documentID;
    }
    return self;
}

@end
