//
//  CBLReadOnlyDocument.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyDocument.h"
#import "CBLDocument+Internal.h"

@implementation CBLReadOnlyDocument

@synthesize documentID=_documentID, c4Doc=_c4Doc;


- (instancetype) initWithDocumentID: (NSString*)documentID
                              c4Doc: (nullable CBLC4Document*)c4Doc
                         fleeceData: (nullable CBLFLDict*)data
{
    NSParameterAssert(documentID != nil);
    self = [super initWithFleeceData: data];
    if (self) {
        _documentID = documentID;
        _c4Doc = c4Doc;
    }
    return self;
}


#pragma mark - Public


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, self.documentID];
}


- (BOOL) isDeleted {
    return _c4Doc != nil ? (_c4Doc.flags & kDeleted) != 0 : NO;
}


- (uint64_t) sequence {
    return _c4Doc != nil ? _c4Doc.sequence : 0;
}


#pragma mark - Internal


- (NSUInteger) generation {
    return _c4Doc != nil ? c4rev_getGeneration(_c4Doc.revID) : 0;
}


- (BOOL) exists {
    return _c4Doc != nil ? (_c4Doc.flags & kExists) != 0 : NO;
}


@end
