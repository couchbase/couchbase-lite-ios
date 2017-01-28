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
#import "CBLConflictResolver.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLJSON.h"
#import "CBLInternal.h"
#include "c4Observer.h"

NSString* const kCBLDocumentChangeNotification = @"CBLDocumentChangeNotification";
NSString* const kCBLDocumentSavedNotification = @"CBLDocumentSavedNotification";
NSString* const kCBLDocumentIsExternalUserInfoKey = @"CBLDocumentIsExternalUserInfoKey";


@implementation CBLDocument {
    C4Database* _c4db;
    C4Document* _c4doc;
}

@synthesize documentID=_documentID, database=_database, conflictResolver = _conflictResolver;


- (instancetype) initWithDatabase: (CBLDatabase*)db
                            docID: (NSString*)docID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError {
    self = [super init];
    if (self) {
        _database = db;
        _documentID = docID;
        _c4db = db.c4db;
        if (![self loadDoc: outError mustExist: mustExist])
            return nil;
    }
    return self;
}


- (void) dealloc {
    c4doc_free(_c4doc);
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _documentID];
}


- (BOOL) exists {
    return (_c4doc->flags & kExists) != 0;
}


- (BOOL) isDeleted {
    return (_c4doc->flags & kDeleted) != 0;
}


- (uint64_t) sequence {
    return _c4doc->sequence;
}


- (NSString*) revisionID {
    return slice2string(_c4doc->revID);
}


- (NSUInteger) generation {
    return c4rev_getGeneration(_c4doc->revID);
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
    if (![self exists])
        return NO;
    
    C4Transaction transaction(_c4db);
    if (!transaction.begin())
        return convertError(transaction.error(),  outError);
    
    C4Error err;
    if (c4doc_purgeRevision(_c4doc, C4Slice(), &err) >= 0) {
        if (c4doc_save(_c4doc, 0, &err)) {
            // Save succeeded; now commit:
            if (!transaction.commit()) {
                return convertError(transaction.error(), outError);
            }
            
            // Reload:
            if (![self loadDoc: outError mustExist: NO])
                return NO;
            
            [self resetChanges];
            return YES;
        }
    }
    return convertError(err, outError);
}


- (void) revert {
    [self resetChanges];
}

#pragma mark - CBLProperties


- (FLSharedKeys) sharedKeys {
    return c4db_getFLSharedKeys(_c4db);
}

- (CBLBlob *)blobWithProperties:(NSDictionary *)properties error:(NSError **)error {
    return [[CBLBlob alloc] initWithDatabase: _database properties:properties error:error];
}

- (BOOL)storeBlob:(CBLBlob *)blob error:(NSError **)error {
    return [blob installInDatabase: _database error: error];
}

- (void) setHasChanges: (BOOL)hasChanges {
    if (self.hasChanges != hasChanges) {
        [super setHasChanges: hasChanges];
        [_database document: self hasUnsavedChanges: hasChanges];
    }
}


- (void)setObject:(id)value forKeyedSubscript:(NSString *)key {
    [super setObject:value forKeyedSubscript:key];
    [self noteChanged];
}


- (void)setProperties:(NSDictionary *)properties {
    [super setProperties:properties];
    [self noteChanged];
}


#pragma mark - INTERNAL


- (void)changedExternally {
    // The current API design decision is that when a document has unsaved changes, it should
    // not update with external changes and should not post notifications. Instead the conflict
    // resolution will happen when the app saves the document.

    if(!self.hasChanges) {
        [self loadDoc:nil mustExist:YES];
        [self postChangedNotificationExternal:YES];
    }
}


#pragma mark - PRIVATE


- (void)noteChanged {
    self.hasChanges = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName: kCBLDocumentChangeNotification
                                                        object: self];
}


- (void)postChangedNotificationExternal:(BOOL)external {
    NSDictionary* userInfo = external ? @{kCBLDocumentIsExternalUserInfoKey: @YES} : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName: kCBLDocumentSavedNotification
                                                        object: self
                                                      userInfo: userInfo];
}


- (BOOL) loadDoc: (NSError**)outError mustExist: (BOOL)mustExist {
    auto doc = [self readC4Doc: outError mustExist: mustExist];
    if (!doc)
        return NO;
    [self setC4Doc: doc];
    self.hasChanges = NO;
    return YES;
}


- (C4Document*) readC4Doc: (NSError**)outError mustExist: (BOOL)mustExist {
    CBLStringBytes docId(_documentID);
    C4Error err;
    auto doc = c4doc_get(_c4db, docId, mustExist, &err);
    if (!doc)
        convertError(err, outError);
    return doc;
}


- (void) setC4Doc: (nullable C4Document*)doc {
    c4doc_free(_c4doc);
    _c4doc = doc;
    [self setRootDict: nullptr orProperties: nil];
    if (_c4doc) {
        C4Slice body = _c4doc->selectedRev.body;
        if (body.size > 0) {
            FLDict root = FLValue_AsDict(FLValue_FromTrustedData({body.buf, body.size}));
            [self setRootDict: root orProperties: nil];
        }
    }
}


#pragma mark - SAVING:


- (id<CBLConflictResolver>) effectiveConflictResolver {
    return _conflictResolver ?: _database.conflictResolver;
}


static bool objectContainsBlob(__unsafe_unretained id value) {
    if ([value isKindOfClass: [NSDictionary class]])
        return dictContainsBlob(value);
    else if ([value isKindOfClass: [NSArray class]])
        return arrayContainsBlob(value);
    else
        return false;
}

static bool arrayContainsBlob(__unsafe_unretained NSArray* array) {
    for (id value in array)
        if (objectContainsBlob(value))
            return true;
    return false;
}

static bool dictContainsBlob(__unsafe_unretained NSDictionary* dict) {
    if ([dict[@"_cbltype"] isEqual: @"blob"])
        return true;
    __block bool containsBlob = false;
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        *stop = containsBlob = objectContainsBlob(value);
    }];
    return containsBlob;
}


// Lower-level save method. On conflict, returns YES but sets *outDoc to NULL. */
- (BOOL) saveInto: (C4Document **)outDoc
         asDelete: (BOOL)deletion
            error: (NSError **)outError
{
    //TODO: Need to be able to save a deletion that has properties in it
    NSDictionary* propertiesToSave = deletion ? nil : self.properties;
    CBLStringBytes docTypeSlice;
    C4DocPutRequest put = {
        .docID = _c4doc->docID,
        .history = &_c4doc->revID,
        .historyCount = 1,
        .save = true,
    };
    if (deletion)
        put.revFlags = kRevDeleted;
    if (dictContainsBlob(propertiesToSave))
        put.revFlags |= kRevHasAttachments;
    if (propertiesToSave.count > 0) {
        // Encode properties to Fleece data:
        auto enc = c4db_createFleeceEncoder(_c4db);
        auto body = [self encodeWith:enc error: outError];
        FLEncoder_Free(enc);
        if (!body.buf) {
            *outDoc = nullptr;
            return NO;
        }

        put.body = {body.buf, body.size};
        docTypeSlice = self[@"type"];
        put.docType = docTypeSlice;
    }
    
    // Save to database:
    C4Error err;
    *outDoc = c4doc_put(_c4db, &put, nullptr, &err);
    c4slice_free(put.body);
    
    if (!*outDoc && err.code != kC4ErrorConflict) {     // conflict is not an error, here
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
    C4Error err;
    C4Document *currentDoc = c4doc_get(_c4db, _c4doc->docID, true, &err);
    if (!currentDoc)
        return convertError(err, outError);
    NSDictionary *current = nil;
    auto currentData = currentDoc->selectedRev.body;
    if (currentData.buf) {
        FLValue currentRoot = FLValue_FromTrustedData({currentData.buf, currentData.size});
        current = FLValue_GetNSObject(currentRoot, self.sharedKeys, nil);
    }
    NSDictionary* resolved;
    if (deletion) {
        // Deletion always loses a conflict.
        resolved = current;

    } else if (resolver) {
        resolved = [resolver resolveMine: (self.properties ?: @{})
                              withTheirs: (current ?: @{})
                                 andBase: self.savedProperties];
        if (resolved == nil) {
            // Resolver gave up:
            c4doc_free(currentDoc);
            return convertError({LiteCoreDomain, kC4ErrorConflict}, outError);
        }
    } else {
        // Default resolution algorithm is "most active wins", i.e. higher generation number.
        //TODO: Once conflict resolvers can access the document generation, move this logic
        //      into a default CBLConflictResolver.
        NSUInteger myGgggeneration = self.generation + 1;
        NSUInteger theirGgggeneration = c4rev_getGeneration(currentDoc->revID);
        if (myGgggeneration >= theirGgggeneration)       // hope I die before I get old
            resolved = self.properties;
        else
            resolved = current;
    }

    [self setC4Doc: currentDoc];
    self.properties = resolved;
    if ($equal(resolved, current)) {
        self.hasChanges = NO;
    }
    return YES;
}


/// The main save method.
- (BOOL) saveWithConflictResolver: (id<CBLConflictResolver>)resolver
                         deletion: (bool)deletion
                            error: (NSError**)outError
{
    if (!self.hasChanges && !deletion && self.exists)
        return YES;
    
    C4Transaction transaction(_c4db);
    if (!transaction.begin())
        return convertError(transaction.error(),  outError);
    
    C4Document* newDoc;
    if (![self saveInto: &newDoc asDelete: deletion error: outError])
        return NO;

    if (!newDoc) {
        // There's been a conflict; first merge with the new saved revision:
        if (![self mergeWithConflictResolver: resolver deletion: deletion error: outError])
            return NO;
        // The merge might have turned the save into a no-op:
        if (!self.hasChanges)
            return YES;
        // Now save the merged properties:
        if (![self saveInto: &newDoc asDelete: deletion error: outError])
            return NO;
        Assert(newDoc);     // In a transaction we can't have a second conflict after merging!
    }
    
    // Save succeeded; now commit:
    if (!transaction.commit()) {
        c4doc_free(newDoc);
        return convertError(transaction.error(), outError);
    }
    
    [self setC4Doc: newDoc];
    self.hasChanges = NO;
    if (deletion)
        [self resetChanges];
    [self postChangedNotificationExternal:NO];
    return YES;
}

@end

// TODO:
// * Rollback _c4doc if the transaction is aborted.
// * Post document change notification
// * Conflict resolution
