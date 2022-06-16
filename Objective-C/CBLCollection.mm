//
//  CBLCollection.m
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

#import "CBLCollection+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLIndexable.h"
#import "CBLChangeListenerToken.h"
#import "CBLCollection+Internal.h"
#import "CBLCollectionChangeObservable.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLIndexable.h"
#import "CBLIndexConfiguration+Internal.h"
#import "CBLScope.h"
#import "CBLScope+Internal.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"

using namespace fleece;

NSString* const kCBLDefaultCollectionName = @"_default";

@implementation CBLCollection

@synthesize count=_count, name=_name, scope=_scope, c4col=_c4col, db=_db;

- (instancetype) initWithDB: (CBLDatabase*)db
               c4collection: (C4Collection*)c4collection {
    CBLAssertNotNil(db);
    CBLAssertNotNil(c4collection);
    self = [super init];
    if (self) {
        C4CollectionSpec spec = c4coll_getSpec(c4collection);
        
        _db = db;
        _c4col = c4coll_retain(c4collection);
        _name = slice2string(spec.name);
        _scope = [[CBLScope alloc] initWithDB: db name: slice2string(spec.scope)];
        
        CBLLogVerbose(Database, @"%@ Creating collection:%@ db=%@ scope=%@",
                      self, _name, db, _scope);
    }
    
    return self;
}

- (void) dealloc {
    c4coll_release(_c4col);
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@.%@]%@", self.class, _scope.name, _name, _db];
}

#pragma mark - Indexable

- (BOOL) createIndexWithName: (NSString*)name
                      config: (CBLIndexConfiguration *)config
                       error: (NSError**)error {
    CBLAssertNotNil(name);
    CBLAssertNotNil(config);
    
    CBLDatabase* db = _db;
    CBL_LOCK(db) {
        if (![self collectionIsValid: error])
            return NO;
        
        CBLStringBytes iName(name);
        CBLStringBytes c4IndexSpec(config.getIndexSpecs);
        C4IndexOptions options = config.indexOptions;
        
        C4Error c4err = {};
        return c4coll_createIndex(_c4col,
                                  iName,
                                  c4IndexSpec,
                                  config.queryLanguage,
                                  config.indexType,
                                  &options,
                                  &c4err) || convertError(c4err, error);
    }
}

- (BOOL) deleteIndexWithName: (NSString*)name
                       error: (NSError**)error {
    CBLAssertNotNil(name);
    CBLDatabase* db = _db;
    CBL_LOCK(db) {
        if (![self collectionIsValid: error])
            return NO;
        
        C4Error c4err = {};
        CBLStringBytes iName(name);
        return c4coll_deleteIndex(_c4col, iName, &c4err) || convertError(c4err, error);
    }
}

- (nullable NSArray*) indexes: (NSError**)error {
    CBLDatabase* db = _db;
    CBL_LOCK(db) {
        if (![self collectionIsValid: error])
            return nil;
        
        C4Error err = {};
        C4SliceResult res = c4coll_getIndexesInfo(_c4col, &err);
        if (err.code != 0){
            convertError(err, error);
            return nil;
        }
        
        FLDoc doc = FLDoc_FromResultData(res, kFLTrusted, nullptr, nullslice);
        FLSliceResult_Release(res);
        
        NSArray* indexes = FLValue_GetNSObject(FLDoc_GetRoot(doc), nullptr);
        FLDoc_Release(doc);
        
        // extract only names
        NSMutableArray* ins = [NSMutableArray arrayWithCapacity: indexes.count];
        for (NSDictionary* dict in indexes) {
            [ins addObject: dict[@"name"]];
        }
        return [NSArray arrayWithArray: ins];
    }
}

#pragma mark - Document Change Listeners

- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)listenerID
                                                listener: (void (^)(CBLDocumentChange*))listener {
    // TODO: add the implementation, returning a token to avoid the warning
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil];
    return token;
}

- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)listenerID
                                                   queue: (dispatch_queue_t)queue
                                                listener: (void (^)(CBLDocumentChange*))listener {
    // TODO: add the implementation, returning a token to avoid the warning
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil];
    return token;
}

#pragma mark - Document management

- (CBLDocument*) documentWithID: (NSString*)docID error: (NSError**)error {
    CBL_LOCK(_db) {
        if (![self collectionIsValid: error])
            return nil;
        
        // TODO: nested lock!
        if ([_db isClosedLocked]) {
            CBLWarn(Database, @"%@ Database is closed!", self);
            if (error)
                *error = CBLCollectionErrorNotOpen;
            
            return nil;
        }
        
        return [[CBLDocument alloc] initWithCollection: self
                                            documentID: docID
                                        includeDeleted: NO
                                                 error: error];
    }
}

- (NSDate*) getDocumentExpirationWithID: (NSString*)documentID error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(_db) {
        if (![self collectionIsValid: error])
            return nil;
        
        CBLStringBytes docID(documentID);
        C4Error c4err = {};
        int64_t timestamp = c4coll_getDocExpiration(_c4col, docID, &c4err);
        if (timestamp == -1) {
            convertError(c4err, error);
            return nil;
        }
        
        if (timestamp == 0) {
            return nil;
        }
        return [NSDate dateWithTimeIntervalSince1970: (timestamp/msec)];
    }
}

- (BOOL) setDocumentExpirationWithID: (NSString*)documentID
                          expiration: (NSDate*)date
                               error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(_db) {
        if (![self collectionIsValid: error])
            return NO;
        
        UInt64 timestamp = date ? (UInt64)(date.timeIntervalSince1970*msec) : 0;
        C4Error err;
        CBLStringBytes docID(documentID);
        return c4coll_setDocExpiration(_c4col, docID, timestamp, &err) || convertError(err, error);
    }
    
    return NO;
}

- (BOOL) deleteDocument: (CBLDocument*)document
     concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                  error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) deleteDocument: (CBLDocument*)document
                  error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
      conflictHandler: (BOOL (^)(CBLMutableDocument*, CBLDocument *))conflictHandler
                error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
                error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) purgeDocument: (CBLDocument*)document
                 error: (NSError**)error {
    CBLAssertNotNil(document);
    
    CBL_LOCK(_db) {
        if ([_db isClosedLocked]) {
            if (error)
                *error = CBLCollectionErrorNotOpen;
            return NO;
        }
        
        if (![_db prepareDocument: document error: error])
            return NO;
        
        if (!document.revisionID)
            return createError(CBLErrorNotFound,
                               @"Document doesn't exist in the collection.", error);
        
        if ([self purgeDocumentWithID: document.id error: error]) {
            [document replaceC4Doc: nil];
            return TRUE;
        }
        
        return NO;
    }
}

- (BOOL) purgeDocumentWithID: (NSString*)documentID
                       error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(_db) {
        if ([_db isClosedLocked]) {
            if (error)
                *error = CBLCollectionErrorNotOpen;
            return NO;
        }
        
        C4Transaction transaction(_db.c4db);
        if (!transaction.begin())
            return convertError(transaction.error(),  error);
        
        C4Error err = {};
        CBLStringBytes docID(documentID);
        if (c4coll_purgeDoc(_c4col, docID, &err)) {
            if (!transaction.commit()) {
                return convertError(transaction.error(), error);
            }
            return YES;
        }
        return convertError(err, error);
    }
}

#pragma mark - Change Listener

- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLCollectionChange*))listener {
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil];
    return token;
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLCollectionChange*))listener {
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil];
    return token;
}

#pragma mark - Internal

- (BOOL) collectionIsValid: (NSError**)error {
    BOOL valid = c4coll_isValid(_c4col);
    if (!valid) {
        if (error)
            *error = CBLCollectionErrorNotOpen;
    }
    
    return valid;
    
}

@end
