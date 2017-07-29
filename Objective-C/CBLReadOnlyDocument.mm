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
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"


@implementation CBLReadOnlyDocument {
    CBLC4Document* _c4Doc;
}


@synthesize database=_database, id=_id;
@synthesize lock=_lock;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                            c4Doc: (nullable CBLC4Document*)c4Doc
                       fleeceData: (nullable CBLFLDict*)data
{
    NSParameterAssert(documentID != nil);
    self = [super initWithFleeceData: data];
    if (self) {
        _database = database;
        _id = documentID;
        _c4Doc = c4Doc;
        _lock = [[NSObject alloc] init];
    }
    return self;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError
{
    // This is always called under the database's lock from the CBLDatabase class.
    self = [self initWithDatabase: database documentID: documentID c4Doc: nil fleeceData: nil];
    if (self) {
        _database = database;
        CBLStringBytes docId(documentID);
        C4Error err;
        
        auto doc = c4doc_get(self.c4db, docId, mustExist, &err);
        if (doc == nullptr) {
            convertError(err, outError);
            return nil;
        }
        [self setC4Doc: [CBLC4Document document: doc]];
    }
    return self;
}


#pragma mark - Public


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, self.id];
}


- (BOOL) isDeleted {
    CBL_LOCK(_lock) {
        return _c4Doc != nil ? (_c4Doc.flags & kDocDeleted) != 0 : NO;
    }
}


- (uint64_t) sequence {
    CBL_LOCK(_lock) {
        return _c4Doc != nil ? _c4Doc.sequence : 0;
    }
}


#pragma mark - Internal


- (C4Database*) c4db {
    C4Database* db = _database.c4db; // .c4db is thread-safe
    Assert(db, @"%@ does not belong to a database", self);
    return db;
}


- (void) setC4Doc:(CBLC4Document *)c4Doc {
    CBL_LOCK(_lock) {
        _c4Doc = c4Doc;
        
        if (c4Doc) {
            FLDict root = nullptr;
            C4Slice body = c4Doc.selectedRev.body;
            if (body.size > 0)
                root = FLValue_AsDict(FLValue_FromTrustedData({body.buf, body.size}));
            self.data = [[CBLFLDict alloc] initWithDict: root datasource: c4Doc database: _database];
        } else {
            self.data = nil;
        }
    }
}


- (CBLC4Document*) c4Doc {
    CBL_LOCK(_lock) {
        return _c4Doc;
    }
}


- (BOOL) selectConflictingRevision {
    CBL_LOCK(_lock) {
        if (!_c4Doc || !c4doc_selectNextLeafRevision(_c4Doc.rawDoc, false, true, nullptr))
            return NO;
        self.c4Doc = _c4Doc;     // This will update to the selected revision
        return YES;
    }
}


- (BOOL) selectCommonAncestorOfDoc: (CBLReadOnlyDocument*)doc1 andDoc: (CBLReadOnlyDocument*)doc2 {
    CBL_LOCK(_lock) {
        CBLStringBytes rev1(doc1.revID), rev2(doc2.revID);
        if (!_c4Doc || !c4doc_selectCommonAncestorRevision(_c4Doc.rawDoc, rev1, rev2)
            || !c4doc_hasRevisionBody(_c4Doc.rawDoc))
            return NO;
        self.c4Doc = _c4Doc;     // This will update to the selected revision
        return YES;
    }
}


- (NSString*) revID {
    CBL_LOCK(_lock) {
        return _c4Doc != nil ?  slice2string(_c4Doc.rawDoc->selectedRev.revID) : nil;
    }
}


- (NSUInteger) generation {
    CBL_LOCK(_lock) {
        // CBLDocument overrides this
        return _c4Doc != nil ? c4rev_getGeneration(_c4Doc.rawDoc->selectedRev.revID) : 0;
    }
}


- (BOOL) exists {
    CBL_LOCK(_lock) {
        return _c4Doc != nil ? (_c4Doc.flags & kDocExists) != 0 : NO;
    }
}


- (id<CBLConflictResolver>) effectiveConflictResolver {
    return self.database.config.conflictResolver ?: [CBLDefaultConflictResolver new];
}


- (NSData*) encode: (NSError**)outError {
    CBL_LOCK(_lock) {
        // CBLDocument overrides this
        fleece::slice body = _c4Doc.rawDoc->selectedRev.body;
        return body ? body.copiedNSData() : [NSData data];
    }
}


@end
