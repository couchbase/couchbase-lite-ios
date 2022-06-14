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

#import "CBLCollection.h"
#import "CBLIndexable.h"
#import "CBLChangeListenerToken.h"
#import "CBLCollectionChangeObservable.h"
#import "CBLDatabase+Internal.h"
#import "CBLStringBytes.h"
#import "CBLScope.h"
#import "CBLIndexConfiguration+Internal.h"
#import "CBLStatus.h"
#import "CBLScope+Internal.h"

using namespace fleece;

NSString* const kCBLDefaultCollectionName = @"_default";

@implementation CBLCollection {
    __weak CBLDatabase* _db;
    C4Collection* _c4col;
}

@synthesize count=_count, name=_name, scope=_scope;

- (instancetype) initWithDB: (CBLDatabase*)db
             collectionName: (NSString*)collectionName
                  scopeName: (NSString*)scopeName
                      error: (NSError**)error {
    CBLAssertNotNil(db);
    CBLAssertNotNil(collectionName);
    
    self = [super init];
    if (self) {
        _db = db;
        _name = collectionName;
        
        scopeName = scopeName.length > 0 ? scopeName : kCBLDefaultScopeName;
        CBLStringBytes cName(collectionName);
        CBLStringBytes sName(scopeName);
        C4CollectionSpec spec = { .name = cName, .scope = sName };
        
        __block C4Collection* c;
        __block C4Error err = {};
        [db safeBlock:^{
            c = c4db_getCollection(db.c4db, spec);
            if (!c) {
                // collection doesn't exists, create one
                c = c4db_createCollection(db.c4db, spec, &err);
            }
        }];
        
        if (err.code != 0) {
            // TODO: Add to CBLErrorMessage : CBL-3296
            CBLWarn(Database, @"%@ Failed to create new collection (%d/%d)",
                    self, err.code, err.domain);
            convertError(err, error);
            return nil;
        }
        
        _scope = [[CBLScope alloc] initWithDB: db name: scopeName error: error];
        
        _c4col = c;
    }
    return self;
}

- (void) dealloc {
    _db = nil;
    _c4col = nil;
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
    __block BOOL success = NO;
    __block C4Error c4err;
    [db safeBlock: ^{
        CBLStringBytes iName(name);
        CBLStringBytes c4IndexSpec(config.getIndexSpecs);
        C4IndexOptions options = config.indexOptions;
        
        success = c4coll_createIndex(_c4col, iName, c4IndexSpec, config.queryLanguage,
                                          config.indexType, &options, &c4err);
    }];
    
    return success || convertError(c4err, error);
}

- (BOOL) deleteIndexWithName: (NSString*)name
                       error: (NSError**)error {
    CBLAssertNotNil(name);
    
    CBLDatabase* db = _db;
    __block BOOL success = NO;
    __block C4Error c4err;
    [db safeBlock: ^{
        CBLStringBytes iName(name);
        success = c4coll_deleteIndex(_c4col, iName, &c4err);
    }];
    
    return success || convertError(c4err, error);
}

- (nullable NSArray*) indexes: (NSError**)error {
    CBLDatabase* db = _db;
    __block NSMutableArray* ins = nil;
    [db safeBlock: ^{
        [self collectionIsValid];
        
        C4Error err = {};
        C4SliceResult res = c4coll_getIndexesInfo(_c4col, &err);
        FLDoc doc = FLDoc_FromResultData(res, kFLTrusted, nullptr, nullslice);
        FLSliceResult_Release(res);
        
        NSArray* indexes = FLValue_GetNSObject(FLDoc_GetRoot(doc), nullptr);
        FLDoc_Release(doc);
        
        // extract only names
        ins = [NSMutableArray arrayWithCapacity: indexes.count];
        for (NSDictionary* dict in indexes) {
            [ins addObject: dict[@"name"]];
        }
    }];
    
    return [NSArray arrayWithArray: ins];
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

- (CBLDocument*) documentWithID: (NSString*)docID error: (NSError**)error {
    // TODO: add implementation
    return nil;
}

- (NSDate*) getDocumentExpirationWithID: (NSString*)docID error: (NSError**)error {
    // TODO: add implementation
    return nil;
}

- (BOOL) purgeDocument: (CBLDocument*)document
                 error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) purgeDocumentWithID: (NSString*)documentID
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

- (BOOL) setDocumentExpirationWithID: (NSString*)documentID
                          expiration: (NSDate*)date
                               error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

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

- (BOOL) collectionIsValid {
    BOOL valid = c4coll_isValid(_c4col);
    if (!valid) {
        // TODO: Add to CBLErrorMessage : CBL-3296
        [NSException raise: NSInternalInconsistencyException
                    format: @"Collection has been deleted, or its database closed."];
    }
    
    return valid;
    
}

@end
