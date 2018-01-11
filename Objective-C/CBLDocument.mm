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


@synthesize database=_database, id=_id, c4Doc=_c4Doc, fleeceData=_fleeceData;
@synthesize isInvalidated=_isInvalidated;


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                            c4Doc: (nullable CBLC4Document*)c4Doc
{
    NSParameterAssert(documentID != nil);
    self = [super init];
    if (self) {
        _database = database;
        _id = documentID;
        [self setC4Doc: c4Doc];
    }
    return self;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                   includeDeleted: (BOOL)includeDeleted
                            error: (NSError**)outError
{
    self = [self initWithDatabase: database documentID: documentID c4Doc: nil];
    if (self) {
        _database = database;
        CBLStringBytes docId(documentID);
        C4Error err;
        auto doc = c4doc_get(database.c4db, docId, true, &err);
        if (!doc) {
            convertError(err, outError);
            return nil;
        }
        
        if (!includeDeleted && (doc->flags & kDocDeleted) != 0) {
            c4doc_free(doc);
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


- (CBLMutableDocument*) mutableCopyWithZone:(NSZone *)zone {
    return [[CBLMutableDocument alloc] initAsCopyWithDocument: self dict: nil];
}


- (CBLMutableDocument*) toMutable {
    return [self mutableCopy];
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


- (BOOL) isEmpty {
    return _dict.count == 0;
}


- (void) updateDictionary {
    if (_fleeceData) {
        _root.reset(new MRoot<id>(new cbl::DocContext(_database, _c4Doc), Dict(_fleeceData), self.isMutable));
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
    _fleeceData = nullptr;

    if (c4doc) {
        C4Slice body = c4doc.selectedRev.body;
        if (body.size > 0)
            _fleeceData = FLValue_AsDict(FLValue_FromTrustedData({body.buf, body.size}));
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


- (nullable id)valueForKey:(nonnull NSString *)key {
    return [_dict valueForKey: key];
}


- (nullable NSString *)stringForKey:(nonnull NSString *)key {
    return [_dict stringForKey: key];
}


- (nullable NSNumber *)numberForKey:(nonnull NSString *)key {
    return [_dict numberForKey: key];
}


- (NSInteger)integerForKey:(nonnull NSString *)key {
    return [_dict integerForKey: key];
}


- (long long)longLongForKey:(nonnull NSString *)key {
    return [_dict longLongForKey: key];
}


- (float)floatForKey:(nonnull NSString *)key {
    return [_dict floatForKey: key];
}


- (double)doubleForKey:(nonnull NSString *)key {
    return [_dict doubleForKey: key];
}


- (BOOL)booleanForKey:(nonnull NSString *)key {
    return [_dict booleanForKey: key];
}


- (nullable NSDate *)dateForKey:(nonnull NSString *)key {
    return [_dict dateForKey: key];
}


- (nullable CBLBlob *)blobForKey:(nonnull NSString *)key {
    return [_dict blobForKey: key];
}


- (nullable CBLArray *)arrayForKey:(nonnull NSString *)key {
    return [_dict arrayForKey: key];
}


- (nullable CBLDictionary *)dictionaryForKey:(nonnull NSString *)key {
    return [_dict dictionaryForKey: key];
}


- (BOOL)containsValueForKey:(nonnull NSString *)key {
    return [_dict booleanForKey: key];
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


- (NSDictionary<NSString *,id> *)toDictionary {
    return [_dict toDictionary];
}


#pragma mark - Equality


- (BOOL) isEqual: (id)object {
    if (self == object)
        return YES;
    
    CBLDocument* other = $castIf(CBLDocument, object);
    if (!other)
        return NO;
    
    if (![self.database isEqual: other.database]) {
        if (self.database) {
            if (!(other.database && [self.database.name isEqual: other.database.name]))
                return NO;
        } else {
            if (other.database != nil)
                return NO;
        }
    }
    
    if (![self.id isEqualToString: other.id])
        return NO;
    
    return [_dict isEqual: other->_dict];
}


- (NSUInteger) hash {
    return [self.database.name hash] ^  [self.id hash] ^ [_dict hash];
}

@end
