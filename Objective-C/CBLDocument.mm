//
//  CBLDocument.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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


- (uint64_t) sequence {
    CBL_LOCK(self) {
        return _c4Doc != nil ? _c4Doc.sequence : 0;
    }
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
        CBL_LOCK(_database) {
            _dict = _root->asNative();
        }
    } else {
        // New document:
        _root.reset();
        _dict = self.isMutable ? (id)[[CBLNewDictionary alloc] init]
                               : [[CBLDictionary alloc] initEmpty];
    }
}


- (CBLC4Document*) c4Doc {
    CBL_LOCK(self) {
        return _c4Doc;
    }
}


- (void) setC4Doc: (CBLC4Document*)c4doc {
    CBL_LOCK(self) {
        _c4Doc = c4doc;
        _fleeceData = nullptr;
        
        if (c4doc) {
            C4Slice body = c4doc.body;
            if (body.size > 0)
                _fleeceData = FLValue_AsDict(FLValue_FromTrustedData({body.buf, body.size}));
        }
        [self updateDictionary];
    }
}


- (void) replaceC4Doc: (CBLC4Document*)c4doc {
    CBL_LOCK(self) {
        _c4Doc = c4doc;
    }
}


- (NSData*) encode: (NSError**)outError {
    // CBLMutableDocument overrides this
    fleece::slice body = _c4Doc.body;
    return body ? body.copiedNSData() : [NSData data];
}


#pragma mark - For Replication's conflict resolution


- (BOOL) selectConflictingRevision {
    CBL_LOCK(self) {
        if (!_c4Doc || !c4doc_selectNextLeafRevision(_c4Doc.rawDoc, false, true, nullptr))
            return NO;
        
        self.c4Doc = _c4Doc;     // This will update to the selected revision
        return YES;
    }
}


- (BOOL) selectCommonAncestorOfDoc: (CBLDocument*)doc1
                            andDoc: (CBLDocument*)doc2
{
    CBL_LOCK(self) {
        CBLStringBytes rev1(doc1.revID), rev2(doc2.revID);
        if (!_c4Doc || !c4doc_selectCommonAncestorRevision(_c4Doc.rawDoc, rev1, rev2)
            || !c4doc_hasRevisionBody(_c4Doc.rawDoc))
            return NO;
        self.c4Doc = _c4Doc;     // This will update to the selected revision
        return YES;
    }
}


- (NSString*) revID {
    CBL_LOCK(self) {
        return _c4Doc != nil ?  slice2string(_c4Doc.revID) : nil;
    }
}


- (NSUInteger) generation {
    // CBLMutableDocument overrides this
    CBL_LOCK(self) {
        return _c4Doc != nil ? c4rev_getGeneration(_c4Doc.revID) : 0;
    }
}


- (BOOL) isDeleted {
    CBL_LOCK(self) {
        return _c4Doc != nil ? (_c4Doc.flags & kDocDeleted) != 0 : NO;
    }
}


#pragma mark - CBLDictionary


- (NSUInteger) count {
    return _dict.count;
}


- (NSArray*) keys {
    return _dict.keys;
}


- (nullable id) valueForKey: (nonnull NSString*)key {
    return [_dict valueForKey: key];
}


- (nullable NSString*) stringForKey: (nonnull NSString*)key {
    return [_dict stringForKey: key];
}


- (nullable NSNumber*) numberForKey: (nonnull NSString*)key {
    return [_dict numberForKey: key];
}


- (NSInteger) integerForKey:(nonnull NSString*)key {
    return [_dict integerForKey: key];
}


- (long long) longLongForKey: (nonnull NSString*)key {
    return [_dict longLongForKey: key];
}


- (float) floatForKey: (nonnull NSString*)key {
    return [_dict floatForKey: key];
}


- (double) doubleForKey: (nonnull NSString*)key {
    return [_dict doubleForKey: key];
}


- (BOOL) booleanForKey: (nonnull NSString*)key {
    return [_dict booleanForKey: key];
}


- (nullable NSDate*) dateForKey: (nonnull NSString*)key {
    return [_dict dateForKey: key];
}


- (nullable CBLBlob*) blobForKey: (nonnull NSString*)key {
    return [_dict blobForKey: key];
}


- (nullable CBLArray*) arrayForKey: (nonnull NSString*)key {
    return [_dict arrayForKey: key];
}


- (nullable CBLDictionary*) dictionaryForKey:(nonnull NSString*)key {
    return [_dict dictionaryForKey: key];
}


- (BOOL) containsValueForKey: (nonnull NSString *)key {
    return [_dict booleanForKey: key];
}


- (CBLFragment *) objectForKeyedSubscript: (NSString *)key {
    return [_dict objectForKeyedSubscript: key];
}

- (NSUInteger) countByEnumeratingWithState: (nonnull NSFastEnumerationState *)state
                                   objects: (id  _Nullable __unsafe_unretained * _Nonnull)buffer
                                     count: (NSUInteger)len
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
