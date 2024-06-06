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
#import "CBLConflict+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocumentChangeNotifier.h"
#import "CBLDocument+Internal.h"
#import "CBLErrorMessage.h"
#import "CBLIndexable.h"
#import "CBLIndexConfiguration+Internal.h"
#import "CBLIndex+Internal.h"
#import "CBLQueryIndex+Internal.h"
#import "CBLScope.h"
#import "CBLScope+Internal.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"

#define msec 1000.0

using namespace fleece;

NSString* const kCBLDefaultCollectionName = @"_default";

@implementation CBLCollection {
    C4DatabaseObserver* _colObs;
    CBLChangeNotifier<CBLCollectionChange*>* _colChangeNotifier;
    NSMutableDictionary<NSString*,CBLDocumentChangeNotifier*>* _docChangeNotifiers;
    
    // retained database mutex
    id _mutex;
}

@synthesize count=_count, name=_name, scope=_scope, weakdb=_weakdb, strongdb=_strongdb;
@synthesize dispatchQueue=_dispatchQueue;
@synthesize c4col=_c4col;

- (instancetype) initWithDB: (CBLDatabase*)db
               c4collection: (C4Collection*)c4collection
                     cached: (BOOL)cached {
    CBLAssertNotNil(db);
    CBLAssertNotNil(c4collection);
    self = [super init];
    if (self) {
        C4CollectionSpec spec = c4coll_getSpec(c4collection);
        
        if (cached) {
            _weakdb = db;
        } else {
            _strongdb = db;
        }
        
        _c4col = c4coll_retain(c4collection);
        _name = slice2string(spec.name);
        _scope = [[CBLScope alloc] initWithDB: db name: slice2string(spec.scope) cached: cached];
        
        NSString* qName = $sprintf(@"Collection <%p: %@>", self, self);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        _mutex = db.mutex;
    }
    
    return self;
}

- (void) dealloc {
    c4coll_release(_c4col);
    
    [self freeC4Observer];
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@@%p[name=%@]", self.class, self, self.fullName];
}

- (NSUInteger) hash {
    return [self.name hash] ^ [self.scope.name hash] ^ [self.database.path hash];
}

- (id) copyWithZone: (nullable NSZone*)zone {
    return [[[self class] alloc] initWithDB: self.database c4collection: _c4col cached: NO];
}

#pragma mark - Properties

- (NSString*) fullName {
    return $sprintf(@"%@.%@", _scope.name, _name);
}

- (uint64_t) count {
    CBL_LOCK(_mutex) {
        _count = c4coll_isValid(_c4col) ? c4coll_getDocumentCount(_c4col) : 0;
    }
    return _count;
}

- (CBLDatabase*) database {
    if (_strongdb) {
        return _strongdb;
    } else {
        CBLDatabase* db = _weakdb;
        assert(db);
        return db;
    }
}

#pragma mark - Indexable

- (BOOL) createIndexWithName: (NSString*)name
                      config: (CBLIndexConfiguration *)config
                       error: (NSError**)error {
    CBLAssertNotNil(name);
    CBLAssertNotNil(config);
    
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
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

- (BOOL) createIndex: (CBLIndex*)index name:(NSString*)name error: (NSError**)error {
    CBLAssertNotNil(name);
    CBLAssertNotNil(index);
    
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
            return NO;

        CBLStringBytes iName(name);
        CBLStringBytes c4IndexSpec(index.getIndexSpecs);
        C4IndexOptions options = index.indexOptions;

        C4Error c4err = {};
        return c4coll_createIndex(_c4col,
                                  iName,
                                  c4IndexSpec,
                                  index.queryLanguage,
                                  index.indexType,
                                  &options,
                                  &c4err) || convertError(c4err, error);
    }
}

- (BOOL) deleteIndexWithName: (NSString*)name
                       error: (NSError**)error {
    CBLAssertNotNil(name);
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
            return NO;
        
        C4Error c4err = {};
        CBLStringBytes iName(name);
        return c4coll_deleteIndex(_c4col, iName, &c4err) || convertError(c4err, error);
    }
}

- (nullable NSArray*) indexes: (NSError**)error {
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
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
    return [self addDocumentChangeListenerWithID: listenerID queue: nil listener: listener];
}

- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)listenerID
                                                   queue: (dispatch_queue_t)queue
                                                listener: (void (^)(CBLDocumentChange*))listener {
    return [self addDocumentChangeListenerWithDocumentID: listenerID
                                                listener: listener
                                                   queue: queue];
}

#pragma mark get doc

- (CBLDocument*) documentWithID: (NSString*)documentID error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
            return nil;
        
        NSError* err = nil;
        CBLDocument* doc = [[CBLDocument alloc] initWithCollection: self
                                                        documentID: documentID
                                                    includeDeleted: NO
                                                             error: &err];
        
        if (!doc && err.code != CBLErrorNotFound) {
            if (error)
                *error = err;
        }
        
        return doc;
    }
}

#pragma mark - Subscript

- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID {
    NSError* error;
    CBLDocument* doc = [self documentWithID: documentID error: &error];
    if (error) {
        CBLWarn(Database, @"%@: Error when getting a document with ID '%@': %@", self, documentID, error.description);
    }
    return [[CBLDocumentFragment alloc] initWithDocument: doc];
}

#pragma mark - Purge

- (BOOL) purgeDocument: (CBLDocument*)document
                 error: (NSError**)error {
    CBLAssertNotNil(document);
    
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
            return NO;
        
        if (![self prepareDocument: document error: error])
            return NO;
        
        if (!document.revisionID)
            return createError(CBLErrorNotFound,
                               kCBLErrorMessageDocumentNotFoundInCollection, error);
        
        if ([self purgeDocumentWithID: document.id error: error]) {
            [document replaceC4Doc: nil];
            return YES;
        }
        
        return NO;
    }
}

- (BOOL) purgeDocumentWithID: (NSString*)documentID
                       error: (NSError**)error {
    CBLAssertNotNil(documentID);
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
            return NO;
        
        CBLDatabase* db = self.database;
        if (![self database: db isValid: error])
            return NO;
        
        C4Transaction transaction(db.c4db);
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

#pragma mark - Delete Document

- (BOOL) deleteDocument: (CBLDocument*)document
                  error: (NSError**)error {
    return [self deleteDocument: document
             concurrencyControl: kCBLConcurrencyControlLastWriteWins
                          error: error];
}

- (BOOL) deleteDocument: (CBLDocument*)document
     concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                  error: (NSError**)error {
    CBLAssertNotNil(document);
    
    return [self saveDocument: document
             withBaseDocument: nil
           concurrencyControl: concurrencyControl
                   asDeletion: YES
                        error: error];
}

#pragma mark - Save

- (BOOL) saveDocument: (CBLMutableDocument*)document
                error: (NSError**)error {
    return [self saveDocument: document
           concurrencyControl: kCBLConcurrencyControlLastWriteWins
                        error: error];
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                error: (NSError**)error {
    CBLAssertNotNil(document);
    
    return [self saveDocument: document
             withBaseDocument: nil
           concurrencyControl: concurrencyControl
                   asDeletion: NO
                        error: error];
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
      conflictHandler: (BOOL (^)(CBLMutableDocument*, CBLDocument *))conflictHandler
                error: (NSError**)error {
    CBLAssertNotNil(document);
    CBLAssertNotNil(conflictHandler);
    
    CBLDocument* oldDoc = nil;
    NSError* err;
    while (true) {
        BOOL success = [self saveDocument: document
                         withBaseDocument: oldDoc
                       concurrencyControl: kCBLConcurrencyControlFailOnConflict
                               asDeletion: NO
                                    error: &err];
        // if it's a conflict, we will use the conflictHandler to resolve.
        if (!success && $equal(err.domain, CBLErrorDomain) && err.code == CBLErrorConflict) {
            CBL_LOCK(_mutex) {
                oldDoc = [[CBLDocument alloc] initWithCollection: self
                                                    documentID: document.id
                                                includeDeleted: YES
                                                         error: error];
                if (!oldDoc)
                    return createError(CBLErrorNotFound, error);
            }
            
            @try {
                if (conflictHandler(document, oldDoc.isDeleted ? nil : oldDoc)) {
                    continue;
                } else {
                    return createError(CBLErrorConflict, error);
                }
            } @catch(NSException* ex) {
                CBLWarn(Database, @"Exception while resolving through save handler. Exception: %@",
                        ex.description);
                if (error)
                    *error = [NSError errorWithDomain: CBLErrorDomain
                                                 code: CBLErrorConflict
                                             userInfo: @{NSLocalizedDescriptionKey: ex.description}];
            }
            return NO;
        } else if (!success) { // any other error, we return false with errorInfo
            if (error)
                *error = err;
            
            return NO;
        }
        
        // save didn't cause any error
        return YES;
    }
    
    return NO;
}

#pragma mark - Doc Expiry

- (NSDate*) getDocumentExpirationWithID: (NSString*)documentID error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
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
    
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
            return NO;
        
        UInt64 timestamp = date ? (UInt64)(date.timeIntervalSince1970*msec) : 0;
        C4Error err;
        CBLStringBytes docID(documentID);
        return c4coll_setDocExpiration(_c4col, docID, timestamp, &err) || convertError(err, error);
    }
    
    return NO;
}

- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLCollectionChange*))listener {
    return [self addChangeListenerWithQueue: nil listener: listener];
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLCollectionChange*))listener {
    CBLAssertNotNil(listener);
    
    CBL_LOCK(_mutex) {
        NSError* error = nil;
        if (![self checkIsValid: &error]) {
            CBLWarn(Database,
                    @"%@: Cannot add change listener. Database is closed or collection is removed.", self);
        }
        
        return [self addCollectionChangeListener: listener queue: queue];
    }
}

#pragma mark - Internal

- (BOOL) checkIsValid: (NSError**)error {
    BOOL valid = c4coll_isValid(_c4col);
    if (!valid) {
        if (error)
            *error = CBLCollectionErrorNotOpen;
    }
    
    return valid;
}

- (BOOL) isValid {
    return [self checkIsValid: nil];
}

- (BOOL) database: (CBLDatabase*)db isValid: (NSError**)error {
    BOOL valid = db != nil;
    if (!valid) {
        if (error)
            *error = CBLDatabaseErrorNotOpen;
    }
    
    return valid;
}

- (C4CollectionSpec) c4spec {
    // Convert to cString directly instead of using CBLStringBytes to avoid
    // stack-use-after-scope problem when a small string is kept in the
    // _local stack based buffer of the CBLStringBytes
    C4Slice name = c4str([_name cStringUsingEncoding: NSUTF8StringEncoding]);
    C4Slice scopeName = c4str([_scope.name cStringUsingEncoding: NSUTF8StringEncoding]);
    return { .name = name, .scope = scopeName };
}

- (BOOL) isEqual: (id)object {
    if (self == object)
        return YES;
    
    CBLCollection* other = $castIf(CBLCollection, object);
    if (!other)
        return NO;
    
    if (!(other && [self.name isEqual: other.name] &&
          [self.scope.name isEqual: other.scope.name] &&
          [self.database.path isEqual: other.database.path])) {
        return NO;
    }
    
    if (!self.isValid || !other.isValid)
        return NO;
    
    return YES;
}

- (id<CBLListenerToken>) addCollectionChangeListener: (void (^)(CBLCollectionChange*))listener
                                               queue: (dispatch_queue_t)queue {
    if (!_colChangeNotifier) {
        _colChangeNotifier = [CBLChangeNotifier new];
        C4Error c4err = {};
        _colObs = c4dbobs_createOnCollection(_c4col, colObserverCallback, (__bridge void *)self, &c4err);
        if (!_colObs) {
            CBLWarn(Database, @"%@ Failed to create collection obs c4col=%p err=%d/%d",
                    self, _c4col, c4err.domain, c4err.code);
        }
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
    CBL_LOCK(_mutex) {
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
    CBL_LOCK(_mutex) {
        CBLChangeListenerToken* t = (CBLChangeListenerToken*)token;
        if (t.context)
            [self removeDocumentChangeListenerWithToken: token];
        else {
            if ([_colChangeNotifier removeChangeListenerWithToken: token] == 0) {
                c4dbobs_free(_colObs);
                _colObs = nil;
                _colChangeNotifier = nil;
            }
        }
    }
}

- (void) removeDocumentChangeListenerWithToken: (CBLChangeListenerToken*)token {
    CBL_LOCK(_mutex) {
        NSString* documentID = (NSString*)token.context;
        CBLDocumentChangeNotifier* notifier = _docChangeNotifiers[documentID];
        if (notifier && [notifier removeChangeListenerWithToken: token] == 0) {
            [notifier stop];
            [_docChangeNotifiers removeObjectForKey:documentID];
        }
    }
}

- (void) freeC4Observer {
    c4dbobs_free(_colObs);
    _colObs = nullptr;
    _colChangeNotifier = nil;

    [_docChangeNotifiers.allValues makeObjectsPerformSelector: @selector(stop)];
    _docChangeNotifiers = nil;
}

#pragma mark - Document listener

- (id<CBLListenerToken>) addDocumentChangeListenerWithDocumentID: documentID
                                                        listener: (void (^)(CBLDocumentChange*))listener
                                                           queue: (dispatch_queue_t)queue {
    CBL_LOCK(_mutex) {
        if (!_docChangeNotifiers)
            _docChangeNotifiers = [NSMutableDictionary dictionary];
        
        CBLDocumentChangeNotifier* docNotifier = _docChangeNotifiers[documentID];
        if (!docNotifier) {
            docNotifier = [[CBLDocumentChangeNotifier alloc] initWithCollection: self documentID: documentID];
            _docChangeNotifiers[documentID] = docNotifier;
        }
        
        CBLChangeListenerToken* token = [docNotifier addChangeListenerWithQueue: queue
                                                                       listener: listener
                                                                       delegate: self];
        token.context = documentID;
        return token;
    }
}

#pragma mark save

- (BOOL) saveDocument: (CBLDocument*)document
     withBaseDocument: (nullable CBLDocument*)baseDoc
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
           asDeletion: (BOOL)deletion
                error: (NSError**)outError {
    
    if (deletion && !document.revisionID)
        return createError(CBLErrorNotFound,
                           kCBLErrorMessageDeleteDocFailedNotSaved, outError);
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: outError])
            return NO;
        
        CBLDatabase* db = self.database;
        if (![self database: db isValid: outError])
            return NO;
        
        if (![self prepareDocument: document error: outError])
            return NO;
        
        C4Document* curDoc = nil;
        C4Document* newDoc = nil;
        @try {
            // Begin a db transaction:
            C4Transaction transaction(db.c4db);
            if (!transaction.begin())
                return convertError(transaction.error(), outError);
            
            if (![self saveDocument: document into: &newDoc withBaseDocument: baseDoc.c4Doc.rawDoc
                         asDeletion: deletion db: db error: outError])
                return NO;
            
            if (!newDoc) {
                // Handle conflict:
                if (concurrencyControl == kCBLConcurrencyControlFailOnConflict)
                    return createError(CBLErrorConflict, outError);
                
                C4Error err;
                CBLStringBytes bDocID(document.id);
                curDoc = c4coll_getDoc(_c4col, bDocID, true, kDocGetCurrentRev, &err);;
                
                // If deletion and the current doc has already been deleted
                // or doesn't exist:
                if (deletion) {
                    if (!curDoc) {
                        if (err.code == kC4ErrorNotFound)
                            return YES;
                        return convertError(err, outError);
                    } else if ((curDoc->flags & kDocDeleted) != 0) {
                        [document replaceC4Doc: [CBLC4Document document: curDoc]];
                        curDoc = nil;
                        return YES;
                    }
                }
                
                // Save changes on the current branch:
                if (!curDoc)
                    return convertError(err, outError);
                
                if (![self saveDocument: document into: &newDoc withBaseDocument: curDoc
                             asDeletion: deletion db: db error: outError])
                    return NO;
            }
            
            if (!transaction.commit())
                return convertError(transaction.error(), outError);
            
            [document replaceC4Doc: [CBLC4Document document: newDoc]];
            newDoc = nil;
            return YES;
        }
        @finally {
            c4doc_release(curDoc);
            c4doc_release(newDoc);
        }
    }
    return NO;
}

// Lower-level save method. On conflict, returns YES but sets *outDoc to NULL.
// call on db-lock(c4doc_create/update)
- (BOOL) saveDocument: (CBLDocument*)document
                 into: (C4Document**)outDoc
     withBaseDocument: (nullable C4Document*)base
           asDeletion: (BOOL)deletion
                   db: (CBLDatabase*)db
                error: (NSError**)outError
{
    C4RevisionFlags revFlags = 0;
    if (deletion)
        revFlags = kRevDeleted;
    FLSliceResult body;
    if (!deletion && !document.isEmpty) {
        // Encode properties to Fleece data:
        body = [document encodeWithRevFlags: &revFlags error: outError];
        if (!body.buf) {
            *outDoc = nullptr;
            return NO;
        }
    } else {
        FLEncoder enc = c4db_getSharedFleeceEncoder(db.c4db);
        FLEncoder_BeginDict(enc, 0);
        FLEncoder_EndDict(enc);
        body = FLEncoder_Finish(enc, nullptr);
        FLEncoder_Reset(enc);
    }
    
    // Save to collection:
    C4Error err;
    C4Document *c4Doc = base != nullptr ? base : document.c4Doc.rawDoc;
    if (c4Doc) {
        *outDoc = c4doc_update(c4Doc, (FLSlice)body, revFlags, &err);
    } else {
        CBLStringBytes docID(document.id);
        *outDoc = c4coll_createDoc(_c4col, docID, (FLSlice)body, revFlags, &err);
    }

    FLSliceResult_Release(body);
    
    if (!*outDoc && !(err.domain == LiteCoreDomain && err.code == kC4ErrorConflict)) {
        // conflict is not an error, at this level
        return convertError(err, outError);
    }
    return YES;
}

- (BOOL) prepareDocument: (CBLDocument*)document error: (NSError**)error {
    if (!document.collection) {
        document.collection = self;
    } else if (document.collection != self) {
        return createError(CBLErrorInvalidParameter,
                           kCBLErrorMessageDocumentAnotherCollection, error);
    }
    return YES;
}

#pragma mark - RESOLVING REPLICATED CONFLICTS:

- (bool) resolveConflictInDocument: (NSString*)docID
              withConflictResolver: (id<CBLConflictResolver>)conflictResolver
                             error: (NSError**)outError {
    while (true) {
        CBLDocument* localDoc;
        CBLDocument* remoteDoc;
        
        // Get latest local and remote document revisions from DB
        CBL_LOCK(_mutex) {
            // Read local document:
            localDoc = [[CBLDocument alloc] initWithCollection: self
                                                    documentID: docID
                                                includeDeleted: YES
                                                  contentLevel: kDocGetCurrentRev
                                                         error: outError];
            if (!localDoc) {
                CBLWarn(Sync, @"Unable to find the document %@ during conflict resolution,\
                        skipping...", docID);
                return NO;
            }
            
            // Read the conflicting remote revision:
            remoteDoc = [[CBLDocument alloc] initWithCollection: self
                                                     documentID: docID
                                                 includeDeleted: YES
                                                   contentLevel: kDocGetAll
                                                          error: outError];
            if (!remoteDoc || ![remoteDoc selectConflictingRevision]) {
                CBLWarn(Sync, @"Unable to select conflicting revision for %@, the conflict may "
                        "have been resolved...", docID);
                // this means no conflict, so returning success
                return YES;
            }
        }
        
        conflictResolver = conflictResolver ?: [CBLConflictResolver default];
        
        // Resolve conflict:
        CBLDocument* resolvedDoc;
        @try {
            CBLLogInfo(Sync, @"Resolving doc '%@' (localDoc=%@ and remoteDoc=%@)",
                       docID, localDoc.revisionID, remoteDoc.revisionID);
            
            if (localDoc.isDeleted && remoteDoc.isDeleted) {
                resolvedDoc = remoteDoc;
            } else {
                CBLConflict* conflict = [[CBLConflict alloc] initWithID: docID
                                                          localDocument: localDoc.isDeleted ? nil : localDoc
                                                         remoteDocument: remoteDoc.isDeleted ? nil : remoteDoc];
                
                resolvedDoc = [conflictResolver resolve: conflict];
            }
            
            if (resolvedDoc && resolvedDoc.id != docID) {
                CBLWarn(Sync, @"The document ID of the resolved document '%@' is not matching "
                        "with the document ID of the conflicting document '%@'.",
                        resolvedDoc.id, docID);
            }
            
            if (resolvedDoc && resolvedDoc.collection && resolvedDoc.collection != self) {
                [NSException raise: NSInternalInconsistencyException
                            format: kCBLErrorMessageResolvedDocWrongDb,
                 resolvedDoc.collection.name, self.name];
            }
        } @catch (NSException *ex) {
            CBLWarn(Sync, @"Exception in conflict resolver: %@", ex.description);
            *outError = [NSError errorWithDomain: CBLErrorDomain
                                            code: CBLErrorConflict
                                        userInfo: @{NSLocalizedDescriptionKey: ex.description}];
            return NO;
        }
        
        NSError* err;
        BOOL success = [self saveResolvedDocument: resolvedDoc withLocalDoc: localDoc
                                        remoteDoc: remoteDoc error: &err];
        
        if ($equal(err.domain, CBLErrorDomain) && err.code == CBLErrorConflict)
            continue;
        
        if (outError)
            *outError = err;
        
        return success;
    }
}

- (BOOL) saveResolvedDocument: (CBLDocument*)resolvedDoc
                 withLocalDoc: (CBLDocument*)localDoc
                    remoteDoc: (CBLDocument*)remoteDoc
                        error: (NSError**)outError
{
    CBL_LOCK(_mutex) {
        CBLDatabase* db = self.database;
        if (![self database: db isValid: outError])
            return NO;
        
        C4Transaction t(db.c4db);
        if (!t.begin())
            return convertError(t.error(), outError);
        
        if (!resolvedDoc) {
            if (localDoc.isDeleted)
                resolvedDoc = localDoc;
            
            if (remoteDoc.isDeleted)
                resolvedDoc = remoteDoc;
        }
        
        if (resolvedDoc != localDoc)
            resolvedDoc.collection = self;
        
        // The remote branch has to win, so that the doc revision history matches the server's.
        CBLStringBytes winningRevID = remoteDoc.revisionID;
        CBLStringBytes losingRevID = localDoc.revisionID;
        
        // mergedRevFlags:
        C4RevisionFlags mergedFlags = 0;
        
        // mergedBody:
        alloc_slice mergedBody;
        if (resolvedDoc != remoteDoc) {
            if (resolvedDoc) {
                // Unless the remote revision is being used as-is, we need a new revision:
                NSError* err = nil;
                mergedBody = [resolvedDoc encodeWithRevFlags: &mergedFlags error: &err];
                if (err) {
                    createError(CBLErrorUnexpectedError, err.localizedDescription, outError);
                    return NO;
                }
                
                if (!mergedBody) {
                    createError(CBLErrorUnexpectedError, kCBLErrorMessageResolvedDocContainsNull, outError);
                    return NO;
                }
            } else
                mergedBody = [self emptyFLSliceResult: db];
        }
        
        mergedFlags |= resolvedDoc.c4Doc != nil ? resolvedDoc.c4Doc.revFlags : 0;
        if (!resolvedDoc || resolvedDoc.isDeleted)
            mergedFlags |= kRevDeleted;
        
        // Tell LiteCore to do the resolution:
        C4Document *c4doc = localDoc.c4Doc.rawDoc;
        C4Error c4err;
        if (!c4doc_resolveConflict(c4doc,
                                   winningRevID,
                                   losingRevID,
                                   mergedBody,
                                   mergedFlags,
                                   &c4err)
            || !c4doc_save(c4doc, 0, &c4err)) {
            return convertError(c4err, outError);
        }
        CBLLogInfo(Sync, @"Conflict resolved as doc '%@' rev %.*s",
                   localDoc.id, (int)c4doc->revID.size, (char*)c4doc->revID.buf);
        
        return t.commit() || convertError(t.error(), outError);
    }
}

- (FLSliceResult) emptyFLSliceResult: (CBLDatabase*)db {
    FLEncoder enc = c4db_getSharedFleeceEncoder(db.c4db);
    FLEncoder_BeginDict(enc, 0);
    FLEncoder_EndDict(enc);
    auto result = FLEncoder_Finish(enc, nullptr);
    FLEncoder_Reset(enc);
    return result;
}

- (nullable CBLQueryIndex*) getIndex:(nonnull NSString*)name error: (NSError**)error {
    CBLAssertNotNil(name);
    
    CBL_LOCK(_mutex) {
        if (![self checkIsValid: error])
            return nil;
        
        C4Error* c4err = {};
        CBLStringBytes iName(name);
        
        C4Index* c4index = c4coll_getIndex(_c4col, iName, c4err);
        if (c4err) {
            convertError(*c4err, error);
            return nil;
        }
        
        if(c4index){
            CBLQueryIndex* index = [[CBLQueryIndex alloc] initWithIndex:c4index name:name collection:self];
            c4index_release(c4index);
            return index;
        } else{
            return nil;
        }
    }
}

@end
