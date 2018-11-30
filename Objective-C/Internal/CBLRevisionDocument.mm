//
//  CBLRevisionDocument.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/29/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLRevisionDocument.h"
#import "CBLCoreBridge.h"
#import "CBLDocument+Internal.h"
#import "fleece/Fleece.hh"

using namespace fleece;

@implementation CBLRevisionDocument {
    C4RevisionFlags _flags;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (C4String)documentID
                            flags: (C4RevisionFlags)flags
                             body: (FLDict)body
{
    self = [super initWithDatabase: database documentID: slice2string(documentID) body: body];
    if (self) {
        _flags = flags;
    }
    return self;
}

- (BOOL) isDeleted {
    return (_flags & kRevDeleted) != 0;
}

@end
