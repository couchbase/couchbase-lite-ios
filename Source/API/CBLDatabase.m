//
//  CBLDatabase.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrivate.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+LocalDocs.h"
#import "CBL_DatabaseChange.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLModelFactory.h"
#import "CBLCache.h"
#import "CBLManager+Internal.h"
#import "CBLMisc.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif


// NOTE: This file contains mostly just public-API method implementations.
// The lower-level stuff is in CBLDatabase.m, etc.


#define kDocRetainLimit 50

NSString* const kCBLDatabaseChangeNotification = @"CBLDatabaseChange";


static id<CBLFilterCompiler> sFilterCompiler;


@implementation CBLDatabase
{
    CBLCache* _docCache;
    CBLModelFactory* _modelFactory;  // used in category method in CBLModelFactory.m
    NSMutableSet* _unsavedModelsMutable;   // All CBLModels that have unsaved changes
}


@synthesize manager=_manager, unsavedModelsMutable=_unsavedModelsMutable;
@synthesize path=_path, name=_name, isOpen=_isOpen, thread=_thread;


- (instancetype) initWithPath: (NSString*)path
                         name: (NSString*)name
                      manager: (CBLManager*)manager
                     readOnly: (BOOL)readOnly
{
    self = [self _initWithPath: path name: name manager: manager readOnly: readOnly];
    if (self) {
        _unsavedModelsMutable = [NSMutableSet set];
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


- (void) postPublicChangeNotification: (CBL_DatabaseChange*)change {
    CBL_Revision* winningRev = change.winningRevision;
    NSURL* source = change.source;

    // Notify the corresponding instantiated CBLDocument object (if any):
    [[self cachedDocumentWithID: winningRev.docID] revisionAdded: change];

    // Post a database-changed notification, but only post one per runloop cycle by using
    // a notification queue. If the current notification has the "external" flag, make sure
    // it gets posted by clearing any pending instance of the notification that doesn't have
    // the flag.
    NSDictionary* userInfo = source ? $dict({@"external", $true}) : nil;
    NSNotification* n = [NSNotification notificationWithName: kCBLDatabaseChangeNotification
                                                      object: self
                                                    userInfo: userInfo];
    NSNotificationQueue* queue = [NSNotificationQueue defaultQueue];
    if (source != nil)
        [queue dequeueNotificationsMatching: n coalesceMask: NSNotificationCoalescingOnSender];
    [queue enqueueNotification: n
                  postingStyle: NSPostASAP 
                  coalesceMask: NSNotificationCoalescingOnSender
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


- (BOOL) inTransaction: (BOOL(^)(void))block {
    return 200 == [self _inTransaction: ^CBLStatus {
        return block() ? 200 : 999;
    }];
}


- (BOOL) create: (NSError**)outError {
    return [self open: outError];
}


- (BOOL) deleteDatabase: (NSError**)outError {
    LogTo(CBLDatabase, @"Deleting %@", _path);
    [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseWillBeDeletedNotification
                                                        object: self];
    if (_isOpen) {
        if (![self close])
            return NO;
    }
    [_manager _forgetDatabase: self];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    if (!self.exists) {
        return YES;
    }
    return CBLRemoveFileIfExists(_path, outError)
        && CBLRemoveFileIfExists(self.attachmentStorePath, outError);
}


- (BOOL) compact: (NSError**)outError {
    CBLStatus status = [self compact];
    if (CBLStatusIsError(status)) {
        if (outError)
            *outError = CBLStatusToNSError(status, nil);
        return NO;
    }
    return YES;
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


// Appease the compiler; these are actually implemented in CBLDatabase.m
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
        CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: localDocID
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
    NSMutableArray* result = $marray();
    for (CBLReplication* repl in _manager.allReplications) {
        if (repl.localDatabase == self)
            [result addObject: repl];
    }
    return result;
}


- (CBLReplication*) pushToURL: (NSURL*)url {
    return [_manager replicationWithDatabase: self remote: url pull: NO create: YES];
}

- (CBLReplication*) pullFromURL: (NSURL*)url {
    return [_manager replicationWithDatabase: self remote: url pull: YES create: YES];
}

- (NSArray*) replicateWithURL: (NSURL*)otherDbURL exclusively: (bool)exclusively {
    return [_manager createReplicationsBetween: self and: otherDbURL exclusively: exclusively];
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
