//
//  CBLDocument.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDocument.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLNewDictionary.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"
#import "CBLFleece.hh"
#import "MRoot.hh"

using namespace fleece;
using namespace fleeceapi;


@implementation CBLDocument
{
    std::unique_ptr<MRoot<id>> _root;
}


@synthesize database=_database, id=_id, c4Doc=_c4Doc, data=_data;


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                            c4Doc: (nullable CBLC4Document*)c4Doc
                       fleeceData: (nullable FLDict)data
{
    NSParameterAssert(documentID != nil);
    self = [super init];
    if (self) {
        _database = database;
        _id = documentID;
        _c4Doc = c4Doc;
        _data = data;
        [self updateDictionary];
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
    return [NSString stringWithFormat: @"%@[%@]", self.class, self.id];
}


- (BOOL) isDeleted {
    return _c4Doc != nil ? (_c4Doc.flags & kDocDeleted) != 0 : NO;
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


- (bool) isMutable {
    // CBLMutableDocument overrides this
    return false;
}


- (void) updateDictionary {
    if (_data) {
        _root.reset(new MRoot<id>(new cbl::DocContext(_database, _c4Doc), Dict(_data), self.isMutable));
        _dict = _root->asNative();
    } else {
        // New document:
        _root.reset();
        _dict = self.isMutable ? (id)[[CBLNewDictionary alloc] init]
                               : [[CBLDictionary alloc] initEmpty];
    }
}


- (void) setC4Doc: (CBLC4Document*)c4doc {
    _c4Doc = c4doc;
    _data = nullptr;

    if (c4doc) {
        C4Slice body = c4doc.selectedRev.body;
        if (body.size > 0)
            _data = FLValue_AsDict(FLValue_FromTrustedData({body.buf, body.size}));
    }
    [self updateDictionary];
}


- (BOOL) selectConflictingRevision {
    if (!_c4Doc || !c4doc_selectNextLeafRevision(_c4Doc.rawDoc, false, true, nullptr))
        return NO;
    self.c4Doc = _c4Doc;     // This will update to the selected revision
    return YES;
}


- (BOOL) selectCommonAncestorOfDoc: (CBLDocument*)doc1
                            andDoc: (CBLDocument*)doc2
{
    CBLStringBytes rev1(doc1.revID), rev2(doc2.revID);
    if (!_c4Doc || !c4doc_selectCommonAncestorRevision(_c4Doc.rawDoc, rev1, rev2)
                || !c4doc_hasRevisionBody(_c4Doc.rawDoc))
        return NO;
    self.c4Doc = _c4Doc;     // This will update to the selected revision
    return YES;
}


- (NSString*) revID {
    return _c4Doc != nil ?  slice2string(_c4Doc.rawDoc->selectedRev.revID) : nil;
}


- (NSUInteger) generation {
    // CBLMutableDocument overrides this
    return _c4Doc != nil ? c4rev_getGeneration(_c4Doc.rawDoc->selectedRev.revID) : 0;
}


- (BOOL) exists {
    return _c4Doc != nil ? (_c4Doc.flags & kDocExists) != 0 : NO;
}


- (id<CBLConflictResolver>) effectiveConflictResolver {
    return self.database.config.conflictResolver ?: [CBLDefaultConflictResolver new];
}


- (NSData*) encode: (NSError**)outError {
    // CBLMutableDocument overrides this
    fleece::slice body = _c4Doc.rawDoc->selectedRev.body;
    return body ? body.copiedNSData() : [NSData data];
}


#pragma mark - CBLDictionary


- (NSUInteger) count {
    return _dict.count;
}

- (NSArray*) keys {
    return _dict.keys;
}

- (nullable CBLArray *)arrayForKey:(nonnull NSString *)key {
    return [_dict arrayForKey: key];
}

- (nullable CBLBlob *)blobForKey:(nonnull NSString *)key {
    return [_dict blobForKey: key];
}

- (BOOL)booleanForKey:(nonnull NSString *)key {
    return [_dict booleanForKey: key];
}

- (BOOL)containsObjectForKey:(nonnull NSString *)key {
    return [_dict booleanForKey: key];
}

- (nullable NSDate *)dateForKey:(nonnull NSString *)key {
    return [_dict dateForKey: key];
}

- (nullable CBLDictionary *)dictionaryForKey:(nonnull NSString *)key {
    return [_dict dictionaryForKey: key];
}

- (double)doubleForKey:(nonnull NSString *)key {
    return [_dict doubleForKey: key];
}

- (float)floatForKey:(nonnull NSString *)key {
    return [_dict floatForKey: key];
}

- (NSInteger)integerForKey:(nonnull NSString *)key {
    return [_dict integerForKey: key];
}

- (long long)longLongForKey:(nonnull NSString *)key {
    return [_dict longLongForKey: key];
}

- (nullable NSNumber *)numberForKey:(nonnull NSString *)key {
    return [_dict numberForKey: key];
}

- (nullable id)objectForKey:(nonnull NSString *)key {
    return [_dict objectForKey: key];
}

- (nullable NSString *)stringForKey:(nonnull NSString *)key {
    return [_dict stringForKey: key];
}

- (CBLFragment *)objectForKeyedSubscript:(NSString *)key {
    return [_dict objectForKeyedSubscript: key];
}

- (NSUInteger)countByEnumeratingWithState:(nonnull NSFastEnumerationState *)state
                                  objects:(id  _Nullable __unsafe_unretained * _Nonnull)buffer
                                    count:(NSUInteger)len
{
    return [_dict countByEnumeratingWithState: state objects: buffer count: len];
}

- (nonnull NSDictionary<NSString *,id> *)toDictionary {
    return [_dict toDictionary];
}

@end
