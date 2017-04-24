//
//  CBLDocumentFragment.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDocumentFragment.h"
#import "CBLDocument.h"

@implementation CBLDocumentFragment {
    CBLDocument* _doc;
}

- /* internal */ (instancetype) initWithDocument: (CBLDocument*)document {
    self = [super init];
    if (self) {
        _doc = document;
    }
    return self;
}


- (BOOL) exists {
    return _doc != nil;
}


- (CBLDocument*) document {
    return _doc;
}


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    return [_doc objectForKeyedSubscript: key];
}


@end
