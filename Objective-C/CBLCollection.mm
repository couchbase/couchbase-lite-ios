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

#import "CBLChangeListenerToken.h"
#import "CBLChangeNotifier.h"
#import "CBLCollection+Internal.h"
#import "CBLCollectionChange.h"
#import "CBLCollectionChangeObservable.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLIndexable.h"
#import "CBLIndexConfiguration+Internal.h"
#import "CBLScope.h"
#import "CBLScope+Internal.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"

using namespace fleece;

NSString* const kCBLDefaultCollectionName = @"_default";

@implementation CBLCollection {
    C4Collection* _c4col;
    
    C4DatabaseObserver* _colObs;
    CBLChangeNotifier<CBLCollectionChange*>* _colChangeNotifier;
}

@synthesize count=_count, name=_name, scope=_scope, db=_db;
@synthesize dispatchQueue=_dispatchQueue;

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
        
        NSString* qName = $sprintf(@"Collection <%@: %@>", self, _name);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
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
    
    CBL_LOCK(_db) {
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
    
    CBL_LOCK(_db) {
        if (![self collectionIsValid: error])
            return NO;
        
        C4Error c4err = {};
        CBLStringBytes iName(name);
        return c4coll_deleteIndex(_c4col, iName, &c4err) || convertError(c4err, error);
    }
}

- (nullable NSArray*) indexes: (NSError**)error {
    CBL_LOCK(_db) {
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
    // TODO: Add implementation & Delegate is set to nil
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil
                                                       delegate: nil];
    return token;
}

- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)listenerID
                                                   queue: (dispatch_queue_t)queue
                                                listener: (void (^)(CBLDocumentChange*))listener {
    // TODO: Add implementation & Delegate is set to nil
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil
                                                       delegate: nil];
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

- (CBLDocument*) documentWithID: (NSString*)documentID error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(_db) {
        if (![self collectionIsValid: error])
            return nil;
        
        if ([_db isClosed]) {
            CBLWarn(Database, @"%@ Database is closed!", self);
            if (error)
                *error = CBLCollectionErrorNotOpen;
            
            return nil;
        }
        
        return [[CBLDocument alloc] initWithCollection: self
                                            documentID: documentID
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

- (BOOL) purgeDocument: (CBLDocument*)document
                 error: (NSError**)error {
    CBLAssertNotNil(document);
    
    CBL_LOCK(_db) {
        if ([_db isClosed]) {
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
        if ([_db isClosed]) {
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
    return [self addChangeListenerWithQueue: nil listener: listener];
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLCollectionChange*))listener {
    CBLAssertNotNil(listener);
    
    CBL_LOCK(self) {
        NSError* error = nil;
        if (![self collectionIsValid: &error]) {
            CBLWarn(Database,
                    @"%@ Cannot add change listener. Database is closed or collection is removed.",
                    self);
        }
        
        return [self addCollectionChangeListener: listener queue: queue];
    }
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

- (id<CBLListenerToken>) addCollectionChangeListener: (void (^)(CBLCollectionChange*))listener
                                               queue: (dispatch_queue_t)queue {
    if (!_colChangeNotifier) {
        _colChangeNotifier = [CBLChangeNotifier new];
        _colObs = c4dbobs_createOnCollection(_c4col, colObserverCallback, (__bridge void *)self);
    }
    
    return [_colChangeNotifier addChangeListenerWithQueue: queue listener: listener delegate: self];
}

static void colObserverCallback(C4CollectionObserver* obs, void* context) {
    CBLCollection *c = (__bridge CBLCollection *)context;
    dispatch_async(c.dispatchQueue, ^{
        [c postCollectionChanged];
    });
}

- (void) postCollectionChanged {
    CBL_LOCK(self) {
        if (!_colObs || !_c4col)
            return;
        
        const uint32_t kMaxChanges = 100u;
        C4DatabaseChange changes[kMaxChanges];
        bool external = false;
        C4CollectionObservation obs = {};
        NSMutableArray* docIDs = [NSMutableArray new];
        do {
            // Read changes in batches of kMaxChanges:
            obs = c4dbobs_getChanges(_colObs, changes, kMaxChanges);
            if (obs.numChanges == 0 || external != obs.external || docIDs.count > 1000) {
                if(docIDs.count > 0) {
                    CBLCollectionChange* change = [[CBLCollectionChange alloc] initWithCollection: self
                                                                                      documentIDs: docIDs
                                                                                       isExternal: external];
                    [_colChangeNotifier postChange: change];
                    docIDs = [NSMutableArray new];
                }
            }
            
            external = obs.external;
            for(uint32_t i = 0; i < obs.numChanges; i++) {
                NSString *docID =slice2string(changes[i].docID);
                [docIDs addObject: docID];
            }
            c4dbobs_releaseChanges(changes, obs.numChanges);
        } while(obs.numChanges > 0);
    }
}

- (void) removeToken: (id)token {
    CBL_LOCK(self) {
        // TODO: handle document change listener as well
            
        if ([_colChangeNotifier removeChangeListenerWithToken: token] == 0) {
            c4dbobs_free(_colObs);
            _colObs = nil;
            _colChangeNotifier = nil;
        }
    }
}

@end
