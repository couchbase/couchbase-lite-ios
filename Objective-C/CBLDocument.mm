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
#import "CBLErrorMessage.h"
#import "CBLData.h"

using namespace fleece;

@implementation CBLDocument
{
    std::unique_ptr<MRoot<id>> _root;
    NSError* _encodingError;
    fleece::MDict<id> _mDict;
    
    BOOL isRemoteDoc;           // Document is from RemoteDB/ConnectedClient
}

@synthesize database=_database, id=_id, c4Doc=_c4Doc, fleeceData=_fleeceData;
@synthesize remoteDocBody=_remoteDocBody;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                            c4Doc: (nullable CBLC4Document*)c4Doc
{
    NSParameterAssert(documentID != nil);
    self = [super init];
    if (self) {
        _database = database;
        _id = documentID;
        _revID = nil;
        [self setC4Doc: c4Doc];
    }
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                             body: (nullable FLDict)body {
    NSParameterAssert(documentID != nil);
    self = [self initWithDatabase: database documentID: documentID c4Doc: nil];
    if (self) {
        _database = database;
        _id = documentID;
        _fleeceData = body;
        _revID = nil;
        [self updateDictionary];
    }
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                       revisionID: (NSString*)revisionID
                             body: (nullable FLDict)body {
    NSParameterAssert(documentID != nil);
    NSParameterAssert(revisionID != nil);
    self = [self initWithDatabase: database documentID: documentID c4Doc: nil];
    if (self) {
        _database = database;
        _id = documentID;
        _fleeceData = body;
        _revID = revisionID;
        [self updateDictionary];
    }
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                   includeDeleted: (BOOL)includeDeleted
                            error: (NSError**)outError
{
    return [self initWithDatabase: database
                       documentID: documentID
                   includeDeleted: includeDeleted
                     contentLevel: kDocGetCurrentRev
                            error: outError];
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                   includeDeleted: (BOOL)includeDeleted
                     contentLevel: (C4DocContentLevel)contentLevel
                            error: (NSError**)outError
{
    self = [self initWithDatabase: database documentID: documentID c4Doc: nil];
    if (self) {
        _database = database;
        _revID = nil;
        CBLStringBytes docId(documentID);
        C4Error err;
        
        auto doc = c4db_getDoc(database.c4db, docId, true, contentLevel, &err);
        if (!doc) {
            convertError(err, outError);
            return nil;
        }
        
        if (!includeDeleted && (doc->flags & kDocDeleted) != 0) {
            c4doc_release(doc);
            return nil;
        }
        
        [self setC4Doc: [CBLC4Document document: doc]];
    }
    return self;
}

// this constructor is used by ConnectedClient APIs
// used to create a CBLDocument without database and c4doc
// will retain the passed in `body`(FLSliceResult)
- (instancetype) initWithDocumentID: (NSString *)documentID
                         revisionID: (NSString *)revisionID
                               body: (FLSliceResult)body {
    NSParameterAssert(documentID != nil);
    NSParameterAssert(revisionID != nil);
    self = [self init];
    if (self) {
        _id = documentID;
        
        _remoteDocBody = FLSliceResult_Retain(body);
        FLDict dict = kFLEmptyDict;
        if (body.buf) {
            FLValue docBodyVal = FLValue_FromData(slice(_remoteDocBody), kFLTrusted);
            dict = FLValue_AsDict(docBodyVal);
        }
        _fleeceData = dict;
        _revID = revisionID;
        isRemoteDoc = true;
        [self updateDictionary];
    }
    return self;
}

- (void) dealloc {
    if (_remoteDocBody)
        FLSliceResult_Release(_remoteDocBody);
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

- (CBLMutableDocument*) mutableCopyWithZone: (NSZone*)zone {
    return isRemoteDoc ?
    [[CBLMutableDocument alloc] initAsCopyOfRemoteDB: self] :
    [[CBLMutableDocument alloc] initAsCopyWithDocument: self dict: nil];
}

- (CBLMutableDocument*) toMutable {
    if (_revID && !_c4Doc && !isRemoteDoc)
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@", kCBLErrorMessageNoDocEditInReplicationFilter];
    return [self mutableCopy];
}

- (NSString*) toJSON {
    return [_dict toJSON];
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
        if (isRemoteDoc) {
            _root.reset(new MRoot<id>(new cbl::RemoteDocContext(), Dict(_fleeceData), self.isMutable));
            _dict = _root->asNative();
        } else {
            _root.reset(new MRoot<id>(new cbl::DocContext(_database, _c4Doc), Dict(_fleeceData), self.isMutable));
            [_database safeBlock:^{
                _dict = _root->asNative();
            }];
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
        
        if (c4doc)
            _fleeceData = c4doc.body;
        
        [self updateDictionary];
    }
}

- (void) replaceC4Doc: (CBLC4Document*)c4doc {
    CBL_LOCK(self) {
        _c4Doc = c4doc;
    }
}

#pragma mark - Fleece Encoding

- (FLSliceResult) encodeWithRevFlags: (C4RevisionFlags*)outRevFlags useSharedEncoder: (BOOL)sharedEncoder error:(NSError**)outError {
    _encodingError = nil;
    auto encoder = sharedEncoder ? c4db_getSharedFleeceEncoder(self.c4db) : FLEncoder_New();
    bool hasAttachment = false;
    FLEncoderContext ctx = { .document = self, .outHasAttachment = &hasAttachment };
    FLEncoder_SetExtraInfo(encoder, &ctx);
    [_dict fl_encodeToFLEncoder: encoder];
    if (_encodingError != nil) {
        FLEncoder_Reset(encoder);
        if (outError)
            *outError = _encodingError;
        _encodingError = nil;
        return {};
    }
    FLError flErr;
    const char* errMessage = FLEncoder_GetErrorMessage(encoder);
    FLSliceResult body = FLEncoder_Finish(encoder, &flErr);
    
    // reset or free the encoder after use
    if (!sharedEncoder)
        FLEncoder_Free(encoder);
    else
        FLEncoder_Reset(encoder);
    
    if (!body.buf)
        createError(flErr, [NSString stringWithUTF8String: errMessage], outError);
    
    if (!hasAttachment) {
        FLDoc doc = FLDoc_FromResultData(body, kFLTrusted, self.database.sharedKeys, nullslice);
        hasAttachment = c4doc_dictContainsBlobs((FLDict)FLDoc_GetRoot(doc));
        FLDoc_Release(doc);
    }
    
    // adds the attachment flag to `outRevFlags`
    if (outRevFlags)
        *outRevFlags |= hasAttachment ? kRevHasAttachments : 0;
    
    return body;
}

// Objects being encoded can call this
- (void) setEncodingError: (NSError*)error {
    if (!_encodingError)
        _encodingError = error;
}

#pragma mark - For Replication's conflict resolution

- (BOOL) selectConflictingRevision {
    CBL_LOCK(self) {
        if (!_c4Doc) {
            [NSException raise: NSInternalInconsistencyException
                        format: @"%@", kCBLErrorMessageNoDocumentRevision];
        }
        
        BOOL foundConflict = NO;
        while(!foundConflict && c4doc_selectNextLeafRevision(_c4Doc.rawDoc, true, true, nullptr)) {
            foundConflict = (_c4Doc.revFlags & kRevIsConflict) != 0;
        }
        if (foundConflict)
            self.c4Doc = _c4Doc;     // This will update to the selected revision
        return foundConflict;
    }
}

- (BOOL) selectCommonAncestorOfDoc: (CBLDocument*)doc1
                            andDoc: (CBLDocument*)doc2
{
    CBL_LOCK(self) {
        CBLStringBytes rev1(doc1.revisionID), rev2(doc2.revisionID);
        if (!_c4Doc || !c4doc_selectCommonAncestorRevision(_c4Doc.rawDoc, rev1, rev2)
            || !c4doc_hasRevisionBody(_c4Doc.rawDoc))
            return NO;
        self.c4Doc = _c4Doc;     // This will update to the selected revision
        return YES;
    }
}

- (NSString*) revisionID {
    CBL_LOCK(self) {
        return _c4Doc != nil ?  slice2string(_c4Doc.revID) : _revID;
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
        return _c4Doc != nil ? (_c4Doc.revFlags & kRevDeleted) != 0 : NO;
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

- (NSUInteger) countByEnumeratingWithState: (nonnull NSFastEnumerationState*)state
                                   objects: (id  _Nullable __unsafe_unretained* _Nonnull)buffer
                                     count: (NSUInteger)len
{
    return [_dict countByEnumeratingWithState: state objects: buffer count: len];
}

- (NSDictionary<NSString *,id>*) toDictionary {
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
