//
//  CBLDatabase.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrivate.h"
#import "CBL_Database+Insertion.h"
#import "CBL_DatabaseChange.h"
#import "CBLModelFactory.h"
#import "CBLCache.h"
#import "CBLManager+Internal.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif


#define kDocRetainLimit 50

NSString* const kCBLDatabaseChangeNotification = @"CBLDatabaseChange";


static id<CBLFilterCompiler> sFilterCompiler;


@implementation CBLDatabase
{
    CBLManager* _manager;
    CBL_Database* _tddb;
    CBLCache* _docCache;
    CBLModelFactory* _modelFactory;  // used in category method in CBLModelFactory.m
    NSMutableSet* _unsavedModelsMutable;   // All CBLModels that have unsaved changes
}


@synthesize tddb=_tddb, manager=_manager, unsavedModelsMutable=_unsavedModelsMutable;


- (instancetype) initWithManager: (CBLManager*)manager
                    CBL_Database: (CBL_Database*)tddb
{
    self = [super init];
    if (self) {
        _manager = manager;
        _tddb = tddb;
        _unsavedModelsMutable = [NSMutableSet set];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(tddbNotification:) name: nil object: tddb];
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


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


// Notified of a change in the CBL_Database:
- (void) tddbNotification: (NSNotification*)n {
    if ([n.name isEqualToString: CBL_DatabaseChangesNotification]) {
        for (CBL_DatabaseChange* change in (n.userInfo)[@"changes"]) {
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
    }
}


- (void) appBackgrounding: (NSNotification*)n {
    [self autosaveAllModels: nil];
}


- (NSString*) name {
    return _tddb.name;
}


- (NSURL*) internalURL {
    return [_manager.internalURL URLByAppendingPathComponent: self.name isDirectory: YES];
}


- (BOOL) inTransaction: (BOOL(^)(void))block {
    return 200 == [_tddb inTransaction: ^CBLStatus {
        return block() ? 200 : 999;
    }];
}


- (BOOL) create: (NSError**)outError {
    return [_tddb open: outError];
}


- (BOOL) deleteDatabase: (NSError**)outError {
    if (![_manager _deleteDatabase: _tddb error: outError])
        return NO;
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    _tddb = nil;
    return YES;
}


- (BOOL) compact: (NSError**)outError {
    CBLStatus status = [_tddb compact];
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
    return [self documentWithID: [CBL_Database generateDocumentID]];
}


- (CBLDocument*) cachedDocumentWithID: (NSString*)docID {
    return (CBLDocument*) [_docCache resourceWithCacheKey: docID];
}


- (void) clearDocumentCache {
    [_docCache forgetAllResources];
}


- (CBLQuery*) queryAllDocuments {
    return [[CBLQuery alloc] initWithDatabase: self view: nil];
}


- (NSUInteger) documentCount {
    return _tddb.documentCount;
}

- (SequenceNumber) lastSequenceNumber {
    return _tddb.lastSequence;
}


#pragma mark - VIEWS:


- (CBLView*) viewNamed: (NSString*)name {
    return [_tddb viewNamed: name];
}


- (NSArray*) allViews {
    return _tddb.allViews;
}


- (CBLQuery*) slowQueryWithMap: (CBLMapBlock)mapBlock {
    return [[CBLQuery alloc] initWithDatabase: self mapBlock: mapBlock];
}


#pragma mark - VALIDATION & FILTERS:


- (void) defineValidation: (NSString*)validationName asBlock: (CBLValidationBlock)validationBlock {
    [_tddb defineValidation: validationName asBlock: validationBlock];
}


- (void) defineFilter: (NSString*)filterName asBlock: (CBLFilterBlock)filterBlock {
    [_tddb defineFilter: filterName asBlock: filterBlock];
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
