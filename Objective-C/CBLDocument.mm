//
//  CBLDocument.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLDocument.h"
#import "CBLArray.h"
#import "CBLC4Document.h"
#import "CBLConflictResolver.h"
#import "CBLCoreBridge.h"
#import "CBLDocument+Internal.h"
#import "CBLInternal.h"
#import "CBLJSON.h"
#import "CBLMisc.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"
#import "CBLStatus.h"


@implementation CBLDocument {
    C4Database* _c4db;      // nullable
    CBLDictionary* _dict;
}


@synthesize database=_database;


+ (instancetype) document {
    return [[self alloc] initWithID: nil];
}


+ (instancetype) documentWithID: (nullable NSString*)documentID {
    return [[self alloc] initWithID: documentID];
}


- (instancetype) init {
    return [self initWithID: nil];
}


- (instancetype) initWithID: (nullable NSString*)documentID {
    self = [super initWithDocumentID: (documentID ?: CBLCreateUUID()) c4Doc: nil fleeceData: nil];
    if (self) {
        _dict = [[CBLDictionary alloc] initWithFleeceData: self.data];
    }
    return self;
}


- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary {
    self = [self initWithID: nil];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


- (instancetype) initWithID: (nullable NSString*)documentID
                 dictionary: (NSDictionary<NSString*,id>*)dictionary
{
    self = [self initWithID: documentID];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


- /* internal */ (instancetype) initWithDatabase: (CBLDatabase*)database
                                      documentID: (NSString*)documentID
                                       mustExist: (BOOL)mustExist
                                           error: (NSError**)outError
{
    self = [super initWithDocumentID: documentID c4Doc: nil fleeceData: nil];
    if (self) {
        self.database = database;
        if (![self loadDoc_mustExist: mustExist error: outError])
            return nil;
    }
    return self;
}


#pragma mark - GETTER


- (NSUInteger) count {
    return _dict.count;
}


- (NSArray*) keys {
    return _dict.keys;
}


- (nullable id) objectForKey: (NSString*)key {
    return [_dict objectForKey: key];
}


- (BOOL) booleanForKey: (NSString*)key {
    return [_dict booleanForKey: key];
}


- (NSInteger) integerForKey: (NSString*)key {
    return [_dict integerForKey: key];
}


- (float) floatForKey: (NSString*)key {
    return [_dict floatForKey: key];
}


- (double) doubleForKey: (NSString*)key {
    return [_dict doubleForKey: key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return [_dict stringForKey: key];
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return [_dict numberForKey: key];
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [_dict dateForKey: key];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return [_dict blobForKey: key];
}


- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key {
    return [_dict dictionaryForKey: key];
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    return [_dict arrayForKey: key];
}


- (BOOL) containsObjectForKey: (NSString*)key {
    return [_dict containsObjectForKey: key];
}


- (NSDictionary<NSString*,id>*) toDictionary {
    return [_dict toDictionary];
}


#pragma mark - SETTER


- (void) setDictionary: (NSDictionary<NSString *,id> *)dictionary {
    [_dict setDictionary: dictionary];
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    [_dict setObject: value forKey: key];
}


- (void) removeObjectForKey:(NSString *)key {
    [_dict removeObjectForKey: key];
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    return [_dict countByEnumeratingWithState: state objects: buffer count: len];
}


#pragma mark - SUBSCRIPTING


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    return [_dict objectForKeyedSubscript: key];
}


#pragma mark - INTERNAL


- (void) setDatabase: (CBLDatabase *)database {
    _database = database;
    _c4db = _database.c4db;
}


- (BOOL) isEmpty {
    return _dict.isEmpty;
}


- (BOOL) save: (NSError**)outError {
    return [self saveWithConflictResolver: self.effectiveConflictResolver
                                 deletion: NO
                                    error: outError];
}


- (BOOL) deleteDocument: (NSError**)outError {
    return [self saveWithConflictResolver: self.effectiveConflictResolver
                                 deletion: YES
                                    error: outError];
}


- (BOOL) purge: (NSError**)outError {
    assert(_database && _c4db);
    
    if (!self.exists) {
        return createError(kCBLStatusNotFound, outError);
    }
    
    C4Transaction transaction(_c4db);
    if (!transaction.begin())
        return convertError(transaction.error(),  outError);
    
    C4Error err;
    if (c4doc_purgeRevision(self.c4Doc.rawDoc, C4Slice(), &err) >= 0) {
        if (c4doc_save(self.c4Doc.rawDoc, 0, &err)) {
            // Save succeeded; now commit:
            if (!transaction.commit())
                return convertError(transaction.error(), outError);
            
            // Reset:
            [self setC4Doc: nil];
            return YES;
        }
    }
    return convertError(err, outError);
}


#pragma mark - PRIVATE


// Reflects only direct changes to the document. Changes on sub dictionaries or arrays will
// not be propagated here.
- (BOOL) changed {
    return _dict.changed;
}


// (Re)loads the document from the db, updating _c4doc and other state.
- (BOOL) loadDoc_mustExist: (BOOL)mustExist error: (NSError**)outError {
    auto doc = [self readC4Doc_mustExist: mustExist error: outError];
    if (!doc)
        return NO;
    [self setC4Doc: [CBLC4Document document: doc]];
    return YES;
}


// Reads the document from the db into a new C4Document and returns it, w/o affecting my state.
- (C4Document*) readC4Doc_mustExist: (BOOL)mustExist error: (NSError**)outError {
    CBLStringBytes docId(self.documentID);
    C4Error err;
    auto doc = c4doc_get(_c4db, docId, mustExist, &err);
    if (!doc)
        convertError(err, outError);
    return doc;
}


// Sets c4doc and updates my root dict
- (void) setC4Doc: (CBLC4Document*)c4doc {
    [super setC4Doc: c4doc];
    
    if (c4doc) {
        FLDict root = nullptr;
        C4Slice body = c4doc.selectedRev.body;
        if (body.size > 0)
            root = FLValue_AsDict(FLValue_FromTrustedData({body.buf, body.size}));
        self.data = [[CBLFLDict alloc] initWithDict: root c4doc: c4doc database: _database];
    } else
        self.data = nil;
    
    // Update delegate dictionary:
    _dict = [[CBLDictionary alloc] initWithFleeceData: self.data];
}


- (id<CBLConflictResolver>) effectiveConflictResolver {
    return _database.config.conflictResolver;
}


// The next three functions search recursively for a property "_cbltype":"blob".

static bool objectContainsBlob(__unsafe_unretained id value) {
    if ([value isKindOfClass: [CBLBlob class]])
        return true;
    else if ([value isKindOfClass: [CBLDictionary class]])
        return dictionaryContainsBlob(value);
    else if ([value isKindOfClass: [CBLArray class]])
        return arrayContainsBlob(value);
    else
        return false;
}

static bool arrayContainsBlob(__unsafe_unretained CBLArray* array) {
    for (id value in array)
        if (objectContainsBlob(value))
            return true;
    return false;
}

static bool dictionaryContainsBlob(__unsafe_unretained CBLDictionary* dict) {
    __block bool containsBlob = false;
    for (NSString* key in dict) {
        containsBlob = objectContainsBlob([dict objectForKey: key]);
        if (containsBlob)
            break;
    }
    return containsBlob;
}

static bool containsBlob(__unsafe_unretained CBLDocument* doc) {
    __block bool containsBlob = false;
    for (NSString* key in doc) {
        containsBlob = objectContainsBlob([doc objectForKey: key]);
        if (containsBlob)
            break;
    }
    return containsBlob;
}


// Lower-level save method. On conflict, returns YES but sets *outDoc to NULL.
// On conflict, returns YES but sets *outDoc to NULL and *outConflict to YES.
// On no changes, no obs, returns YES but sets *outDoc to NULL and *outConflict to NO.
- (BOOL) saveInto: (C4Document **)outDoc
         asDelete: (BOOL)deletion
         conflict: (BOOL*)outConflict
            error: (NSError **)outError
{
    C4RevisionFlags revFlags = 0;
    if (deletion)
        revFlags = kRevDeleted;
    if (containsBlob(self))
        revFlags |= kRevHasAttachments;
    FLSliceResult body = {};
    if (!deletion && !self.isEmpty) {
        // Encode properties to Fleece data:
        auto enc = c4db_createFleeceEncoder(_c4db);
        body = [self encodeWith:enc error: outError];
        FLEncoder_Free(enc);
        if (!body.buf) {
            *outDoc = nullptr;
            *outConflict = NO;
            return NO;
        }
        
        // Compared encoded content to check whether the document has changes or not:
        if (!self.changed && c4SliceEqual(self.c4Doc.selectedRev.body, {body.buf, body.size})) {
            *outDoc = nullptr;
            *outConflict = NO;
            return YES;
        }
    }
    
    // Save to database:
    C4Error err;
    C4Document *c4Doc = self.c4Doc.rawDoc;
    if (c4Doc) {
        *outDoc = c4doc_update(c4Doc, {body.buf, body.size}, revFlags, &err);
    } else {
        CBLStringBytes docID(self.documentID);
        *outDoc = c4doc_create(_c4db, docID, {body.buf, body.size}, revFlags, &err);
    }
    c4slice_free(body);
    
    *outConflict = (err.domain == LiteCoreDomain && err.code == kC4ErrorConflict);
    if (!*outDoc && !(err.domain == LiteCoreDomain && err.code == kC4ErrorConflict)) {
        // conflict is not an error, at this level
        return convertError(err, outError);
    }
    return YES;
}


// "Pulls" from the database, merging the latest revision into the in-memory properties,
//  without saving. */
- (BOOL) mergeWithConflictResolver: (id<CBLConflictResolver>)resolver
                          deletion: (bool)deletion
                             error: (NSError**)outError
{
    // Read the current revision from the database:
    C4Document* rawDoc = [self readC4Doc_mustExist: YES error: outError];
    if (!rawDoc)
        return NO;
    
    FLDict curRoot = nullptr;
    auto curBody = rawDoc->selectedRev.body;
    if (curBody.size > 0)
        curRoot = (FLDict) FLValue_FromTrustedData({curBody.buf, curBody.size});
    
    // Create the current readonly document with the current revision:
    CBLC4Document* curC4doc = [CBLC4Document document: rawDoc];
    CBLFLDict* curDict = [[CBLFLDict alloc] initWithDict: curRoot
                                                   c4doc: curC4doc
                                                database: _database];
    CBLReadOnlyDocument* current = [[CBLReadOnlyDocument alloc] initWithDocumentID: self.documentID
                                                                             c4Doc: curC4doc
                                                                        fleeceData: curDict];
    // Resolve conflict:
    CBLReadOnlyDocument* resolved;
    if (deletion) {
        // Deletion always loses a conflict:
        resolved = current;
    } else if (resolver) {
        // Call the custom conflict resolver:
        CBLReadOnlyDocument* base = [[CBLReadOnlyDocument alloc] initWithDocumentID: self.documentID
                                                                              c4Doc: super.c4Doc
                                                                         fleeceData: super.data];
        CBLConflict* conflict = [[CBLConflict alloc] initWithMine: self theirs: current base: base];
        resolved = [resolver resolve: conflict];
        if (resolved == nil)
            return convertError({LiteCoreDomain, kC4ErrorConflict}, outError);
    } else {
        // Default resolution algorithm is "most active wins", i.e. higher generation number.
        // TODO: Once conflict resolvers can access the document generation, move this logic
        // into a default CBLConflictResolver.
        NSUInteger myGgggeneration = self.generation + 1;
        NSUInteger theirGgggeneration = c4rev_getGeneration(curC4doc.revID);
        if (myGgggeneration >= theirGgggeneration)       // hope I die before I get old
            resolved = self;
        else
            resolved = current;
    }

    // Now update my state to the current C4Document and the merged/resolved properties:
    if (!$equal(resolved, current)) {                   // TODO: Implement deep comparison
        NSDictionary* dict = [resolved toDictionary];   // TODO: toDictionary is expensive
        [self setC4Doc: curC4doc];
        [self setDictionary: dict];
    } else
        [self setC4Doc: curC4doc];
    
    return YES;
}


// The main save method.
- (BOOL) saveWithConflictResolver: (id<CBLConflictResolver>)resolver
                         deletion: (bool)deletion
                            error: (NSError**)outError
{
    assert(_database && _c4db);
    
    if (deletion && !self.exists)
        return createError(kCBLStatusNotFound, outError);
    
    // Begin a db transaction:
    C4Transaction transaction(_c4db);
    if (!transaction.begin())
        return convertError(transaction.error(), outError);

    // Attempt to save. (On conflict, this will succeed but newDoc will be null.)
    C4Document* newDoc;
    BOOL conflict;
    if (![self saveInto: &newDoc asDelete: deletion conflict: &conflict error: outError])
        return NO;
    
    if (!newDoc) {
        // If no conflict, it means no changes, no obs.
        if (!conflict)
            return YES;
        
        // There's been a conflict; first merge with the new saved revision:
        if (![self mergeWithConflictResolver: resolver deletion: deletion error: outError])
            return NO;
        // The merge might have turned the save into a no-op:
        if (!self.changed)
            return YES;
        
        // Now save the merged properties:
        if (![self saveInto: &newDoc asDelete: deletion conflict: &conflict error: outError])
            return NO;
        Assert(newDoc);     // In a transaction we can't have a second conflict after merging!
    }
    
    // Save succeeded; now commit the transaction:
    if (!transaction.commit()) {
        c4doc_free(newDoc);
        return convertError(transaction.error(), outError);
    }

    // Update my state and post a notification:
    [self setC4Doc: [CBLC4Document document: newDoc]];
    
    return YES;
}


#pragma mark - FLEECE ENCODING


- (FLSliceResult) encodeWith: (FLEncoder)encoder error: (NSError**)outError {
    if (![_dict fleeceEncode: encoder database: self.database error: outError])
        return (FLSliceResult){nullptr, 0};
    
    FLError flErr;
    auto body = FLEncoder_Finish(encoder, &flErr);
    if(!body.buf) {
        convertError(flErr, outError);
        return (FLSliceResult){nullptr, 0};
    }
    return body;
}


@end
