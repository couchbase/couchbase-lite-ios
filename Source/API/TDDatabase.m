//
//  TDDatabase.m
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDBPrivate.h"
#import "TD_Database+Insertion.h"
#import "TDModelFactory.h"
#import "TDCache.h"
#import "TD_DatabaseManager.h"


#define kDocRetainLimit 50

NSString* const kTDDatabaseChangeNotification = @"TDDatabaseChange";


@implementation TDDatabase
{
    TDDatabaseManager* _manager;
    TD_Database* _tddb;
    TDCache* _docCache;
    TDModelFactory* _modelFactory;  // used in category method in TDModelFactory.m
    NSMutableSet* _unsavedModelsMutable;   // All TDModels that have unsaved changes
}


@synthesize tddb=_tddb, manager=_manager, unsavedModelsMutable=_unsavedModelsMutable;


- (id) initWithManager: (TDDatabaseManager*)manager
            TD_Database: (TD_Database*)tddb
{
    self = [super init];
    if (self) {
        _manager = manager;
        _tddb = tddb;
        _unsavedModelsMutable = [NSMutableSet set];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(tddbNotification:) name: nil object: tddb];
        if (0)
            _modelFactory = nil;  // appeases static analyzer
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


// Notified of a change in the TD_Database:
- (void) tddbNotification: (NSNotification*)n {
    if ([n.name isEqualToString: TD_DatabaseChangesNotification]) {
        for (NSDictionary* change in (n.userInfo)[@"changes"]) {
            TD_Revision* rev = change[@"winner"];
            NSURL* source = change[@"source"];
            
            [[self cachedDocumentWithID: rev.docID] revisionAdded: rev source: source];

            // Post a database-changed notification, but only post one per runloop cycle by using
            // a notification queue. If the current notification has the "external" flag, make sure
            // it gets posted by clearing any pending instance of the notification that doesn't have
            // the flag.
            NSDictionary* userInfo = source ? $dict({@"external", $true}) : nil;
            NSNotification* n = [NSNotification notificationWithName: kTDDatabaseChangeNotification
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


- (NSString*) name {
    return _tddb.name;
}


- (BOOL) inTransaction: (BOOL(^)(void))block {
    return 200 == [_tddb inTransaction: ^TDStatus {
        return block() ? 200 : 999;
    }];
}


- (BOOL) create: (NSError**)outError {
    return [_tddb open: outError];
}


- (BOOL) deleteDatabase: (NSError**)outError {
    if (![_manager.tdManager deleteDatabase: _tddb error: outError])
        return NO;
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    _tddb.touchDatabase = nil;
    _tddb = nil;
    return YES;
}


#pragma mark - DOCUMENTS:


- (TDDocument*) documentWithID: (NSString*)docID {
    TDDocument* doc = (TDDocument*) [_docCache resourceWithCacheKey: docID];
    if (!doc) {
        if (docID.length == 0)
            return nil;
        doc = [[TDDocument alloc] initWithDatabase: self documentID: docID];
        if (!doc)
            return nil;
        if (!_docCache)
            _docCache = [[TDCache alloc] initWithRetainLimit: kDocRetainLimit];
        [_docCache addResource: doc];
    }
    return doc;
}

- (TDDocument*) objectForKeyedSubscript: (NSString*)key {
    return [self documentWithID: key];
}


- (TDDocument*) untitledDocument {
    return [self documentWithID: [TD_Database generateDocumentID]];
}


- (TDDocument*) cachedDocumentWithID: (NSString*)docID {
    return (TDDocument*) [_docCache resourceWithCacheKey: docID];
}


- (void) clearDocumentCache {
    [_docCache forgetAllResources];
}


- (TDQuery*) queryAllDocuments {
    return [[TDQuery alloc] initWithDatabase: self view: nil];
}


- (NSUInteger) documentCount {
    return _tddb.documentCount;
}

- (SequenceNumber) lastSequenceNumber {
    return _tddb.lastSequence;
}


#pragma mark - VIEWS:


- (TDView*) viewNamed: (NSString*)name {
    TD_View* view = [_tddb viewNamed: name];
    return view ? [[TDView alloc] initWithDatabase: self view: view] : nil;
}


- (NSArray*) allViews {
    return [_tddb.allViews my_map:^id(TD_View* view) {
        return [[TDView alloc] initWithDatabase: self view: view];
    }];
}


- (TDQuery*) slowQueryWithMap: (TDMapBlock)mapBlock {
    return [[TDQuery alloc] initWithDatabase: self mapBlock: mapBlock];
}


#pragma mark - VALIDATION & FILTERS:


- (void) defineValidation: (NSString*)validationName asBlock: (TDValidationBlock)validationBlock {
    TD_ValidationBlock wrapperBlock = nil;
    if (validationBlock) {
        wrapperBlock = ^(TD_Revision* newRevision, id<TD_ValidationContext> context) {
            TDRevision* publicRevision = [[TDRevision alloc] initWithTDDB: _tddb revision: newRevision];
            return validationBlock(publicRevision, context);
        };
    }
    [_tddb defineValidation: validationName asBlock: wrapperBlock];
}


- (void) defineFilter: (NSString*)filterName asBlock: (TDFilterBlock)filterBlock {
    TD_FilterBlock wrapperBlock = nil;
    if (filterBlock) {
        wrapperBlock = ^(TD_Revision* revision, NSDictionary* params) {
            TDRevision* publicRevision = [[TDRevision alloc] initWithTDDB: _tddb revision: revision];
            return filterBlock(publicRevision, params);
        };
    }
    [_tddb defineFilter: filterName asBlock: wrapperBlock];
}


#pragma mark - REPLICATION:


- (NSArray*) allReplications {
    NSMutableArray* result = $marray();
    for (TDReplication* repl in _manager.allReplications) {
        if (repl.localDatabase == self)
            [result addObject: repl];
    }
    return result;
}


- (TDReplication*) pushToURL: (NSURL*)url {
    return [_manager replicationWithDatabase: self remote: url pull: NO create: YES];
}

- (TDReplication*) pullFromURL: (NSURL*)url {
    return [_manager replicationWithDatabase: self remote: url pull: YES create: YES];
}

- (NSArray*) replicateWithURL: (NSURL*)otherDbURL exclusively: (bool)exclusively {
    return [_manager createReplicationsBetween: self and: otherDbURL exclusively: exclusively];
}


@end




@implementation TDDatabase (TDModel)

- (NSArray*) unsavedModels {
    if (_unsavedModelsMutable.count == 0)
        return nil;
    return [_unsavedModelsMutable allObjects];
}

- (BOOL) saveAllModels: (NSError**)outError {
    NSArray* unsaved = self.unsavedModels;
    if (unsaved.count == 0)
        return YES;
    return [TDModel saveModels: unsaved error: outError];
}


@end



@implementation TDDatabase (TDModelFactory)

- (TDModelFactory*) modelFactory {
    if (!_modelFactory)
        _modelFactory = [[TDModelFactory alloc] init];
    return _modelFactory;
}

- (void) setModelFactory:(TDModelFactory *)modelFactory {
    _modelFactory = modelFactory;
}

@end