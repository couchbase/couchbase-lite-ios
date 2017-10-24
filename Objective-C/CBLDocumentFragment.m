//
//  CBLMutableDocumentFragment.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDocumentFragment.h"
#import "CBLMutableDocument.h"
#import "CBLDocument+Internal.h"

@implementation CBLMutableDocumentFragment {
    CBLMutableDocument* _doc;
}

- /* internal */ (instancetype) initWithDocument: (CBLMutableDocument*)document {
    self = [super init];
    if (self) {
        _doc = document;
    }
    return self;
}


- (BOOL) exists {
    return _doc != nil;
}


- (CBLMutableDocument*) document {
    return _doc;
}


- (CBLMutableFragment*) objectForKeyedSubscript: (NSString*)key {
    return _doc ? _doc[key] : nil;
}


@end
