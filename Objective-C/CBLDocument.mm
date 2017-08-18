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
#import "CBLData.h"
#import "CBLCoreBridge.h"
#import "CBLDocument+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CBLJSON.h"
#import "CBLMisc.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"
#import "CBLStatus.h"


@implementation CBLDocument

@synthesize dict=_dict;


#pragma mark - Initializer

+ (instancetype) document {
    return [[self alloc] initWithID: nil];
}


+ (instancetype) documentWithID: (nullable NSString*)documentID {
    return [[self alloc] initWithID: documentID];
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                            c4Doc: (nullable CBLC4Document*)c4Doc
                       fleeceData: (nullable CBLFLDict*)data
{
    self = [super initWithDatabase: database documentID: documentID c4Doc: c4Doc fleeceData: data];
    if (self) {
        _dict = [[CBLDictionary alloc] initWithFleeceData: self.data];
    }
    return self;
}


- (instancetype) init {
    return [self initWithID: nil];
}


- (instancetype) initWithID: (nullable NSString*)documentID {
    return [self initWithDatabase: nil
                       documentID: (documentID ?: CBLCreateUUID())
                            c4Doc: nil
                       fleeceData: nil];
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


#pragma mark - CBLReadOnlyDictionary


- (NSUInteger) count {
    return self.dict.count;
}


- (NSArray*) keys {
    return self.dict.keys;
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    return [self.dict arrayForKey: key];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return [self.dict blobForKey: key];
}


- (BOOL) booleanForKey: (NSString*)key {
    return [self.dict booleanForKey: key];
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [self.dict dateForKey: key];
}


- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key {
    return [self.dict dictionaryForKey: key];
}

- (double) doubleForKey: (NSString*)key {
    return [self.dict doubleForKey: key];
}


- (float) floatForKey: (NSString*)key {
    return [self.dict floatForKey: key];
}


- (NSInteger) integerForKey: (NSString*)key {
    return [self.dict integerForKey: key];
}


- (long long) longLongForKey: (NSString*)key {
    return [self.dict longLongForKey: key];
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return [self.dict numberForKey: key];
}


- (nullable id) objectForKey: (NSString*)key {
    return [self.dict objectForKey: key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return [self.dict stringForKey: key];
}


- (BOOL) containsObjectForKey: (NSString*)key {
    return [self.dict containsObjectForKey: key];
}


- (NSDictionary<NSString*,id>*) toDictionary {
    return [self.dict toDictionary];
}


#pragma mark - CBLDictionary


- (void) setArray: (nullable CBLArray *)value forKey: (NSString *)key {
    [self.dict setArray: value forKey: key];
}


- (void) setBoolean: (BOOL)value forKey: (NSString *)key {
    [self.dict setBoolean: value forKey: key];
}


- (void) setBlob: (nullable CBLBlob*)value forKey: (NSString *)key {
    [self.dict setBlob: value forKey: key];
}


- (void) setDate: (nullable NSDate *)value forKey: (NSString *)key {
    [self.dict setDate: value forKey: key];
}


- (void) setDictionary: (nullable CBLDictionary *)value forKey: (NSString *)key {
    [self.dict setDictionary: value forKey: key];
}


- (void) setDouble: (double)value forKey: (NSString *)key {
    [self.dict setDouble: value forKey: key];
}


- (void) setFloat: (float)value forKey: (NSString *)key {
    [self.dict setFloat: value forKey: key];
}


- (void) setInteger: (NSInteger)value forKey: (NSString *)key {
    [self.dict setInteger: value forKey: key];
}


- (void) setLongLong: (long long)value forKey: (NSString *)key {
    [self.dict setLongLong: value forKey: key];
}


- (void) setNumber: (nullable NSNumber*)value forKey: (NSString *)key {
    [self.dict setNumber: value forKey: key];
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    [self.dict setObject: value forKey: key];
}


- (void) setString: (nullable NSString *)value forKey: (NSString *)key {
    [self.dict setString: value forKey: key];
}


- (void) removeObjectForKey: (NSString *)key {
    [self.dict removeObjectForKey: key];
}


- (void) setDictionary: (NSDictionary<NSString *,id> *)dictionary {
    [self.dict setDictionary: dictionary];
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    return [self.dict countByEnumeratingWithState: state objects: buffer count: len];
}


#pragma mark - Subscript


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    return [self.dict objectForKeyedSubscript: key];
}


#pragma mark - Internal


- (void) setC4Doc: (CBLC4Document*)c4doc {
    [super setC4Doc: c4doc];
    
    // Update delegate dictionary:
    self.dict = [[CBLDictionary alloc] initWithFleeceData: self.data];
}


- (NSUInteger) generation {
    return super.generation + !!self.changed;
}


- (BOOL) isEmpty {
    return self.dict.isEmpty;
}


- (BOOL) save: (NSError**)outError {
    // This method is only called from the CBLDatabase class under
    // the CBLDatabase's lock.
    return [self saveWithConflictResolver: self.effectiveConflictResolver
                                 deletion: NO
                                    error: outError];
}


- (BOOL) deleteDocument: (NSError**)outError {
    // This method is only called from the CBLDatabase class under
    // the CBLDatabase's lock.
    return [self saveWithConflictResolver: self.effectiveConflictResolver
                                 deletion: YES
                                    error: outError];
}


- (BOOL) purge: (NSError**)outError {
    // This method is only called from the CBLDatabase class under
    // the CBLDatabase's lock.
    if (!self.exists) {
        return createError(kCBLStatusNotFound, outError);
    }
    
    C4Transaction transaction(self.c4db);
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


#pragma mark - Private


// Reflects only direct changes to the document. Changes on sub dictionaries or arrays will
// not be propagated here.
- (BOOL) changed {
    return self.dict.changed;
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


// Lower-level save method. On conflict, returns YES but sets *outDoc to NULL.
- (BOOL) saveInto: (C4Document **)outDoc
         asDelete: (BOOL)deletion
            error: (NSError **)outError
{
    C4RevisionFlags revFlags = 0;
    if (deletion)
        revFlags = kRevDeleted;
    NSData* body = nil;
    C4Slice bodySlice = {};
    if (!deletion && !self.isEmpty) {
        // Encode properties to Fleece data:
        body = [self encode: outError];
        if (!body) {
            *outDoc = nullptr;
            return NO;
        }
        bodySlice = data2slice(body);
        auto root = FLValue_FromTrustedData(bodySlice);
        if (C4Doc_ContainsBlobs((FLDict)root, self.database.sharedKeys))
            revFlags |= kRevHasAttachments;
    }
    
    // Save to database:
    C4Error err;
    C4Document *c4Doc = self.c4Doc.rawDoc;
    if (c4Doc) {
        *outDoc = c4doc_update(c4Doc, bodySlice, revFlags, &err);
    } else {
        CBLStringBytes docID(self.id);
        *outDoc = c4doc_create(self.c4db, docID, data2slice(body), revFlags, &err);
    }

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
    if (!resolver)
        return convertError({LiteCoreDomain, kC4ErrorConflict}, outError);

    // Read the current revision from the database:
    auto database = self.database;
    CBLReadOnlyDocument* current = [[CBLReadOnlyDocument alloc] initWithDatabase: database
                                                                      documentID: self.id
                                                                       mustExist: YES
                                                                           error: outError];
    if (!current)
        return NO;
    CBLC4Document* curC4doc = current.c4Doc;

    // Resolve conflict:
    CBLReadOnlyDocument* resolved;
    if (deletion) {
        // Deletion always loses a conflict:
        resolved = current;
    } else {
        // Call the conflict resolver:
        CBLReadOnlyDocument* base = nil;
        if (super.c4Doc) {
            base = [[CBLReadOnlyDocument alloc] initWithDatabase: database
                                                      documentID: self.id
                                                           c4Doc: super.c4Doc
                                                      fleeceData: super.data];
        }
        
        CBLConflict* conflict = [[CBLConflict alloc] initWithMine: self theirs: current base: base];
        resolved = [resolver resolve: conflict];
        if (resolved == nil)
            return convertError({LiteCoreDomain, kC4ErrorConflict}, outError);
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
    if (deletion && !self.exists)
        return createError(kCBLStatusNotFound, outError);
    
    // Begin a db transaction:
    C4Transaction transaction(self.c4db);
    if (!transaction.begin())
        return convertError(transaction.error(), outError);

    // Attempt to save. (On conflict, this will succeed but newDoc will be null.)
    C4Document* newDoc;
    if (![self saveInto: &newDoc asDelete: deletion error: outError])
        return NO;
    
    if (!newDoc) {
        // There's been a conflict; first merge with the new saved revision:
        if (![self mergeWithConflictResolver: resolver deletion: deletion error: outError])
            return NO;
        // The merge might have turned the save into a no-op:
        if (!self.changed)
            return YES;
        // Now save the merged properties:
        if (![self saveInto: &newDoc asDelete: deletion error: outError])
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


#pragma mark - Fleece Encodable


- (NSData*) encode: (NSError**)outError {
    auto encoder = c4db_createFleeceEncoder(self.c4db);
    if (![self.dict cbl_fleeceEncode: encoder database: self.database error: outError])
        return nil;
    FLError flErr;
    FLSliceResult body = FLEncoder_Finish(encoder, &flErr);
    FLEncoder_Free(encoder);
    if (!body.buf)
        convertError(flErr, outError);
    return sliceResult2data(body);
}


@end
