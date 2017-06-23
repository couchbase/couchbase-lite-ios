//
//  CBLReadOnlyDocument.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyDocument.h"
#import "CBLDocument+Internal.h"
#import "CBLInternal.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"


@implementation CBLReadOnlyDocument


@synthesize database=_database, documentID=_documentID, c4Doc=_c4Doc;


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                            c4Doc: (nullable CBLC4Document*)c4Doc
                       fleeceData: (nullable CBLFLDict*)data
{
    NSParameterAssert(documentID != nil);
    self = [super initWithFleeceData: data];
    if (self) {
        _database = database;
        _documentID = documentID;
        _c4Doc = c4Doc;
    }
    return self;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError
{
    self = [self initWithDatabase: database documentID: documentID c4Doc: nil fleeceData: nil];
    if (self) {
        _database = database;
        CBLStringBytes docId(documentID);
        C4Error err;
        auto doc = c4doc_get(database.c4db, docId, mustExist, &err);
        if (!doc) {
            convertError(err, outError);
            return nil;
        }
        [self setC4Doc: [CBLC4Document document: doc]];
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


- (C4Database*) c4db {
    C4Database* db = _database.c4db;
    Assert(db, @"%@ does not belong to a database", self);
    return db;
}


- (void) setC4Doc: (CBLC4Document*)c4doc {
    _c4Doc = c4doc;

    if (c4doc) {
        FLDict root = nullptr;
        C4Slice body = c4doc.selectedRev.body;
        if (body.size > 0)
            root = FLValue_AsDict(FLValue_FromTrustedData({body.buf, body.size}));
        self.data = [[CBLFLDict alloc] initWithDict: root c4doc: c4doc database: _database];
    } else {
        self.data = nil;
    }
}


- (NSUInteger) generation {
    return _c4Doc != nil ? c4rev_getGeneration(_c4Doc.revID) : 0;
}


- (BOOL) exists {
    return _c4Doc != nil ? (_c4Doc.flags & kExists) != 0 : NO;
}


@end
