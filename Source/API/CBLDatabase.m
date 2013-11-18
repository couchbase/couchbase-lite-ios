//
//  CBLDatabase.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Internal.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+LocalDocs.h"
#import "CBLDatabaseChange.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLModel_Internal.h"
#import "CBLModelFactory.h"
#import "CBLCache.h"
#import "CBLManager+Internal.h"
#import "CBLMisc.h"
#import "MYBlockUtils.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif


// NOTE: This file contains mostly just public-API method implementations.
// The lower-level stuff is in CBLDatabase.m, etc.


// Size of document cache: max # of otherwise-unreferenced docs that will be kept in memory.
#define kDocRetainLimit 50

// Default value for maxRevTreeDepth, the max rev depth to preserve in a prune operation
#define kDefaultMaxRevs 20

NSString* const kCBLDatabaseChangeNotification = @"CBLDatabaseChange";


static id<CBLFilterCompiler> sFilterCompiler;


@implementation CBLDatabase
{
    CBLCache* _docCache;
    CBLModelFactory* _modelFactory;  // used in category method in CBLModelFactory.m
    NSMutableSet* _unsavedModelsMutable;   // All CBLModels that have unsaved changes
    NSMutableSet* _allReplications;
}


@synthesize manager=_manager, unsavedModelsMutable=_unsavedModelsMutable;
@synthesize path=_path, name=_name, isOpen=_isOpen;


- (instancetype) initWithPath: (NSString*)path
                         name: (NSString*)name
                      manager: (CBLManager*)manager
                     readOnly: (BOOL)readOnly
{
    self = [self _initWithPath: path name: name manager: manager readOnly: readOnly];
    if (self) {
        _unsavedModelsMutable = [NSMutableSet set];
        _allReplications = [[NSMutableSet alloc] init];
#if TARGET_OS_IPHONE
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(appBackgrounding:)
                                                     name: UIApplicationWillTerminateNotification
                                                   object: nil];
        // Also clean up when app is backgrounded, on iOS:
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(appBackgrounding:)
                                                     name: UIApplicationDidEnterBackgroundNotification
                                                   object: nil];
#endif
        if (0)
            _modelFactory = nil;  // appeases static analyzer
    }
    return self;
}


- (void)dealloc {
    if (_isOpen) {
        //Warn(@"%@ dealloced without being closed first!", self);
        [self close];
    }
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (void) postPublicChangeNotification: (NSArray*)changes {
    BOOL external = NO;
    for (CBLDatabaseChange* change in changes) {
        // Notify the corresponding instantiated CBLDocument object (if any):
        [[self cachedDocumentWithID: change.documentID] revisionAdded: change];
        if (change.source != nil)
            external = YES;
    }

    // Post the public kCBLDatabaseChangeNotification:
    NSDictionary* userInfo = @{@"changes": changes,
                               @"external": @(external)};
    NSNotification* n = [NSNotification notificationWithName: kCBLDatabaseChangeNotification
                                                      object: self
                                                    userInfo: userInfo];
    NSNotificationQueue* queue = [NSNotificationQueue defaultQueue];
    [queue enqueueNotification: n
                  postingStyle: NSPostASAP 
                  coalesceMask: NSNotificationNoCoalescing
                      forModes: @[NSRunLoopCommonModes]];
}


#if TARGET_OS_IPHONE
- (void) appBackgrounding: (NSNotification*)n {
    [self autosaveAllModels: nil];
}
#endif


- (NSURL*) internalURL {
    return [_manager.internalURL URLByAppendingPathComponent: self.name isDirectory: YES];
}


- (void) doAsync: (void (^)())block {
    if (_dispatchQueue)
        dispatch_async(_dispatchQueue, block);
    else
        MYOnThread(_thread, block);
}


- (void) doSync: (void (^)())block {
    if (_dispatchQueue)
        dispatch_sync(_dispatchQueue, block);
    else
        MYOnThreadSynchronously(_thread, block);
}


- (void) doAsyncAfterDelay: (NSTimeInterval)delay block: (void (^)())block {
    if (_dispatchQueue) {
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
        dispatch_after(popTime, _dispatchQueue, block);
    } else {
        //FIX: This schedules on the _current_ thread, not _thread!
        MYAfterDelay(delay, block);
    }
}


- (BOOL) inTransaction: (BOOL(^)(void))block {
    return 200 == [self _inTransaction: ^CBLStatus {
        return block() ? 200 : 999;
    }];
}


- (BOOL) create: (NSError**)outError {
    return [self open: outError];
}


- (BOOL) close {
    (void)[self saveAllModels: NULL];  // ?? Or should I return NO if this fails?

    if (![self closeInternal])
        return NO;

    [self clearDocumentCache];
    _modelFactory = nil;
    return YES;
}


- (BOOL) closeForDeletion {
    // There is no need to save any changes!
    for (CBLModel* model in _unsavedModelsMutable)
        model.needsSave = false;
    _unsavedModelsMutable = nil;
    [self close];
    [_manager _forgetDatabase: self];
    return YES;
}


- (BOOL) deleteDatabase: (NSError**)outError {
    LogTo(CBLDatabase, @"Deleting %@", _path);
    [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseWillBeDeletedNotification
                                                        object: self];
    if (_isOpen && ![self closeForDeletion])
        return NO;
    [_manager _forgetDatabase: self];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    if (!self.exists) {
        return YES;
    }
    return [[self class] deleteDatabaseFilesAtPath: _path error: outError];
}


- (BOOL) compact: (NSError**)outError {
    NSUInteger pruned;
    CBLStatus status = [self pruneRevsToMaxDepth: 0 numberPruned: &pruned];
    if (status == kCBLStatusOK)
        status = [self compact];
    
    if (CBLStatusIsError(status)) {
        if (outError)
            *outError = CBLStatusToNSError(status, nil);
        return NO;
    }
    return YES;
}

- (NSUInteger) maxRevTreeDepth {
    return [[self infoForKey: @"max_revs"] intValue] ?: kDefaultMaxRevs;
}

- (void) setMaxRevTreeDepth: (NSUInteger)maxRevs {
    [self setInfo: $sprintf(@"%lu", (unsigned long)maxRevs) forKey: @"max_revs"];
    // This property is looked up by pruneRevsToMaxDepth:
}


- (BOOL) replaceUUIDs: (NSError**)outError {
    CBLStatus status = [self setInfo: CBLCreateUUID() forKey: @"publicUUID"];
    if (status == kCBLStatusOK)
        status = [self setInfo: CBLCreateUUID() forKey: @"privateUUID"];
    if (status == kCBLStatusOK)
        return YES;

    if (outError)
        *outError = CBLStatusToNSError(status, nil);
    return NO;
}


#pragma mark - DOCUMENTS:


- (CBLDocument*) documentWithID: (NSString*)docID {
    CBLDocument* doc = (CBLDocument*) [_docCache resourceWithCacheKey: docID];
    if (!doc) {
        if (docID.length == 0)
            return nil;
        doc = [[CBLDocument alloc] initWithDatabase: self documentID: docID];
        if (!doc)
            return nil;
        if (!_docCache)
            _docCache = [[CBLCache alloc] initWithRetainLimit: kDocRetainLimit];
        [_docCache addResource: doc];
    }
    return doc;
}

- (CBLDocument*) objectForKeyedSubscript: (NSString*)key {
    return [self documentWithID: key];
}


- (CBLDocument*) untitledDocument {
    return [self documentWithID: [[self class] generateDocumentID]];
}


- (CBLDocument*) cachedDocumentWithID: (NSString*)docID {
    return (CBLDocument*) [_docCache resourceWithCacheKey: docID];
}


- (void) clearDocumentCache {
    [_docCache forgetAllResources];
}

- (void) removeDocumentFromCache: (CBLDocument*)document {
    [_docCache forgetResource: document];
}

- (CBLQuery*) queryAllDocuments {
    return [[CBLQuery alloc] initWithDatabase: self view: nil];
}


// Appease the compiler; these are actually implemented in CBLDatabase+Internal.m
@dynamic documentCount, lastSequenceNumber;


static NSString* makeLocalDocID(NSString* docID) {
    return [@"_local/" stringByAppendingString: docID];
}


- (NSDictionary*) getLocalDocumentWithID: (NSString*)localDocID {
    return [self getLocalDocumentWithID: makeLocalDocID(localDocID) revisionID: nil].properties;
}

- (BOOL) putLocalDocument: (NSDictionary*)properties
                   withID: (NSString*)localDocID
                    error: (NSError**)outError
{
    localDocID = makeLocalDocID(localDocID);
    __block CBLStatus status;
    BOOL ok = [self inTransaction: ^BOOL {
        // The lower-level local docs API has MVCC and requires the matching prior revision ID.
        // So first get the document to look up its current rev ID:
        CBL_Revision* prevRev = [self getLocalDocumentWithID: localDocID revisionID: nil];
        if (!prevRev && !properties) {
            status = kCBLStatusNotFound;
            return NO;
        }
        CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: localDocID
                                                                        revID: nil
                                                                      deleted: (properties == nil)];
        if (properties)
            rev.properties = properties;
        // Now update the doc (or delete it, if properties is nil):
        return [self putLocalRevision: rev prevRevisionID: prevRev.revID status: &status] != nil;
    }];
    
    if (!ok && outError)
        *outError = CBLStatusToNSError(status, nil);
    return ok;
}

- (BOOL) deleteLocalDocumentWithID: (NSString*)localDocID error: (NSError**)outError {
    return [self putLocalDocument: nil withID: localDocID error: outError];
}


#pragma mark - VIEWS:


- (CBLView*) registerView: (CBLView*)view {
    if (!view)
        return nil;
    if (!_views)
        _views = [[NSMutableDictionary alloc] init];
    _views[view.name] = view;
    return view;
}


- (CBLView*) existingViewNamed: (NSString*)name {
    CBLView* view = _views[name];
    if (view)
        return view;
    view = [[CBLView alloc] initWithDatabase: self name: name];
    if (!view.viewID)
        return nil;
    return [self registerView: view];
}


- (CBLView*) viewNamed: (NSString*)name {
    CBLView* view = _views[name];
    if (view)
        return view;
    return [self registerView: [[CBLView alloc] initWithDatabase: self name: name]];
}


- (CBLQuery*) slowQueryWithMap: (CBLMapBlock)mapBlock {
    return [[CBLQuery alloc] initWithDatabase: self mapBlock: mapBlock];
}


#pragma mark - VALIDATION & FILTERS:


- (void) defineValidation: (NSString*)validationName asBlock: (CBLValidationBlock)validationBlock {
    [self.shared setValue: [validationBlock copy]
                  forType: @"validation" name: validationName inDatabaseNamed: _name];
}

- (CBLValidationBlock) validationNamed: (NSString*)validationName {
    return [self.shared valueForType: @"validation" name: validationName inDatabaseNamed: _name];
}


- (void) defineFilter: (NSString*)filterName asBlock: (CBLFilterBlock)filterBlock {
    [self.shared setValue: [filterBlock copy]
                  forType: @"filter" name: filterName inDatabaseNamed: _name];
}

- (CBLFilterBlock) filterNamed: (NSString*)filterName {
    return [self.shared valueForType: @"filter" name: filterName inDatabaseNamed: _name];
}


+ (void) setFilterCompiler: (id<CBLFilterCompiler>)compiler {
    sFilterCompiler = compiler;
}

+ (id<CBLFilterCompiler>) filterCompiler {
    return sFilterCompiler;
}


#pragma mark - REPLICATION:


- (NSArray*) allReplications {
    return [_allReplications allObjects];
}

- (void) addReplication: (CBLReplication*)repl {
    [_allReplications addObject: repl];
}

- (void) forgetReplication: (CBLReplication*)repl {
    [_allReplications removeObject: repl];
}


- (CBLReplication*) replicationToURL: (NSURL*)url {
    return [[CBLReplication alloc] initWithDatabase: self remote: url pull: NO];
}

- (CBLReplication*) replicationFromURL: (NSURL*)url {
    return [[CBLReplication alloc] initWithDatabase: self remote: url pull: YES];
}


@end




@implementation CBLDatabase (CBLModel)

- (NSArray*) unsavedModels {
    if (_unsavedModelsMutable.count == 0)
        return nil;
    return [_unsavedModelsMutable allObjects];
}

- (BOOL) saveAllModels: (NSError**)outError {
    NSArray* unsaved = self.unsavedModels;
    if (unsaved.count == 0)
        return YES;
    return [CBLModel saveModels: unsaved error: outError];
}


- (BOOL) autosaveAllModels: (NSError**)outError {
    NSArray* unsaved = [self.unsavedModels my_filter: ^int(CBLModel* model) {
        return model.autosaves;
    }];
    if (unsaved.count == 0)
        return YES;
    return [CBLModel saveModels: unsaved error: outError];
}


@end



@implementation CBLDatabase (CBLModelFactory)

- (CBLModelFactory*) modelFactory {
    if (!_modelFactory)
        _modelFactory = [[CBLModelFactory alloc] init];
    return _modelFactory;
}

- (void) setModelFactory:(CBLModelFactory *)modelFactory {
    _modelFactory = modelFactory;
}

@end
