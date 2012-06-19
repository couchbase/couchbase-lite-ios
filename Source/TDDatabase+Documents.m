//
//  TDDatabase+Documents.m
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase+Documents.h"
#import "TDDatabase+Insertion.h"
#import "TDDocument.h"
#import "TDCache.h"


#define kDocRetainLimit 50


@implementation TDDatabase (Documents)


- (TDDocument*) documentWithID: (NSString*)docID {
    TDDocument* doc = (TDDocument*) [_docCache resourceWithCacheKey: docID];
    if (!doc) {
        if (docID.length == 0)
            return nil;
#if 0
        if ([docID hasPrefix: @"_design/"])     // Create a design doc when appropriate
            doc = [[TDDesignDocument alloc] initWithParent: self relativePath: docID];
        else
#endif
            doc = [[TDDocument alloc] initWithDatabase: self
                                            documentID: docID];
        if (!doc)
            return nil;
        if (!_docCache)
            _docCache = [[TDCache alloc] initWithRetainLimit: kDocRetainLimit];
        [_docCache addResource: doc];
        [doc autorelease];
    }
    return doc;
}


- (TDDocument*) untitledDocument {
    return [self documentWithID: [[self class] generateDocumentID]];
}


- (TDDocument*) cachedDocumentWithID: (NSString*)docID {
    return (TDDocument*) [_docCache resourceWithCacheKey: docID];
}


- (void) clearDocumentCache {
    [_docCache forgetAllResources];
}


@end
