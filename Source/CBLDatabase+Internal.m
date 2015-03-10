//
//  CBLDatabase+Internal.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLDatabase+Internal.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase+Insertion.h"
#import "CBL_ForestDBStorage.h"
#import "CBL_SQLiteStorage.h"
#import "CBLInternal.h"
#import "CBLModel_Internal.h"
#import "CBL_Revision.h"
#import "CBLDatabaseChange.h"
#import "CBL_BlobStore.h"
#import "CBL_Puller.h"
#import "CBL_Pusher.h"
#import "CBL_Shared.h"
#import "CBLMisc.h"
#import "CBLDatabase.h"
#import "CouchbaseLitePrivate.h"

#import "MYBlockUtils.h"
#import "ExceptionUtils.h"


NSString* const CBL_DatabaseChangesNotification = @"CBLDatabaseChanges";
NSString* const CBL_DatabaseWillCloseNotification = @"CBL_DatabaseWillClose";
NSString* const CBL_DatabaseWillBeDeletedNotification = @"CBL_DatabaseWillBeDeleted";

NSString* const CBL_PrivateRunloopMode = @"CouchbaseLitePrivate";
NSArray* CBL_RunloopModes;

const CBLChangesOptions kDefaultCBLChangesOptions = {UINT_MAX, 0, NO, NO, YES};

static BOOL sAutoCompact = YES;


@implementation CBLDatabase (Internal)

#define kLocalCheckpointDocId @"CBL_LocalCheckpoint"


+ (void) initialize {
    if (self == [CBLDatabase class]) {
        CBL_RunloopModes = @[NSRunLoopCommonModes, CBL_PrivateRunloopMode];
        [self setAutoCompact: YES];
    }
}


- (id<CBL_Storage>) storage {
    return _storage;
}

- (CBL_BlobStore*) attachmentStore {
    return _attachments;
}

- (NSDate*) startTime {
    return _startTime;
}


- (CBL_Shared*)shared {
#if DEBUG
    if (_manager)
        return _manager.shared;
    // For unit testing purposes we create databases without managers (see createEmptyDBAtPath(),
    // below.) Allow the .shared property to work in this state by creating a per-db instance:
    if (!_debug_shared)
        _debug_shared = [[CBL_Shared alloc] init];
    return _debug_shared;
#else
    return _manager.shared;
#endif
}


+ (BOOL) deleteDatabaseFilesAtPath: (NSString*)dbDir error: (NSError**)outError {
    return CBLRemoveFileIfExists(dbDir, outError);
}


#if DEBUG
+ (instancetype) createEmptyDBAtPath: (NSString*)dir {
    [self setAutoCompact: NO]; // unit tests don't want autocompact
    if (![self deleteDatabaseFilesAtPath: dir error: NULL])
        return nil;
    CBLDatabase *db = [[self alloc] initWithDir: dir name: nil manager: nil readOnly: NO];
    if (![db open: nil])
        return nil;
    AssertEq(db.lastSequenceNumber, 0); // Sanity check that this is not a pre-existing db
    return db;
}
#endif


- (instancetype) _initWithDir: (NSString*)dirPath
                         name: (NSString*)name
                      manager: (CBLManager*)manager
                     readOnly: (BOOL)readOnly
{
    if (self = [super init]) {
        Assert([dirPath hasPrefix: @"/"], @"Path must be absolute");
        _dir = [dirPath copy];
        _manager = manager;
        _name = name ?: [dirPath.lastPathComponent.stringByDeletingPathExtension copy];
        _readOnly = readOnly;

        _dispatchQueue = manager.dispatchQueue;
        if (!_dispatchQueue)
            _thread = [NSThread currentThread];
        _startTime = [NSDate date];
    }
    return self;
}

- (NSString*) description {
    return $sprintf(@"%@[<%p>%@]", [self class], self, self.name);
}

- (BOOL) exists {
    return [[NSFileManager defaultManager] fileExistsAtPath: _dir];
}


+ (void) setAutoCompact:(BOOL)autoCompact {
    sAutoCompact = autoCompact;
}


- (BOOL) open: (NSError**)outError {
    if (_isOpen)
        return YES;
    LogTo(CBLDatabase, @"Opening %@", self);

    // Create the database directory:
    if (![[NSFileManager defaultManager] createDirectoryAtPath: _dir
                                   withIntermediateDirectories: YES
                                                    attributes: nil
                                                         error: outError])
        return NO;

    // Instantiate storage:
    NSString* storageType = _manager.storageType ?: @"SQLite";
    NSString* storageClassName = $sprintf(@"CBL_%@Storage", storageType);
    Class primaryStorage = NSClassFromString(storageClassName);
    Assert(primaryStorage, @"CBLManager.storageType is '%@' but no %@ class found",
           _manager.storageType, storageClassName);
    Assert([primaryStorage conformsToProtocol: @protocol(CBL_Storage)],
            @"CBLManager.storageType is '%@' but %@ is not a CBL_Storage implementation",
            _manager.storageType, storageClassName);
    Class secondaryStorage = NSClassFromString(@"CBL_ForestDBStorage");
    if (primaryStorage == secondaryStorage)
        secondaryStorage = NSClassFromString(@"CBL_SQLiteStorage");
    // Use primary unless dir already contains a db created by secondary:
    id<CBL_Storage> storage = [[secondaryStorage alloc] init];
    if (![storage databaseExistsIn: _dir])
        storage = [[primaryStorage alloc] init];
    LogTo(CBLDatabase, @"Using %@ for db at %@", [storage class], _dir);

    _storage = storage;
    _storage.delegate = self;
    if (![_storage openInDirectory: _dir
                          readOnly: _readOnly
                           manager: _manager
                             error: outError])
        return NO;
    _storage.autoCompact = sAutoCompact;

    // First-time setup:
    if (!self.privateUUID) {
        [_storage setInfo: CBLCreateUUID() forKey: @"privateUUID"];
        [_storage setInfo: CBLCreateUUID() forKey: @"publicUUID"];
    }

    _storage.maxRevTreeDepth = [[_storage infoForKey: @"max_revs"] intValue] ?: kDefaultMaxRevs;

    // Open attachment store:
    NSString* attachmentsPath = self.attachmentStorePath;
    _attachments = [[CBL_BlobStore alloc] initWithPath: attachmentsPath error: outError];
    if (!_attachments) {
        Warn(@"%@: Couldn't open attachment store at %@", self, attachmentsPath);
        [_storage close];
        _storage = nil;
        return NO;
    }

    _isOpen = YES;

    // Listen for _any_ CBLDatabase changing, so I can detect changes made to my database
    // file by other instances (running on other threads presumably.)
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(dbChanged:)
                                                 name: CBL_DatabaseChangesNotification
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(dbChanged:)
                                                 name: CBL_DatabaseWillBeDeletedNotification
                                               object: nil];
    return YES;
}

- (void) _close {
    if (_isOpen) {
        LogTo(CBLDatabase, @"Closing <%p> %@", self, _dir);
        // Don't want any models trying to save themselves back to the db. (Generally there shouldn't
        // be any, because the public -close: method saves changes first.)
        for (CBLModel* model in _unsavedModelsMutable.copy)
            model.needsSave = false;
        _unsavedModelsMutable = nil;
        
        [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseWillCloseNotification
                                                            object: self];
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: CBL_DatabaseChangesNotification
                                                      object: nil];
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: CBL_DatabaseWillBeDeletedNotification
                                                      object: nil];
        for (CBLView* view in _views.allValues)
            [view close];
        
        _views = nil;
        for (CBL_Replicator* repl in _activeReplicators.copy)
            [repl databaseClosing];
        
        _activeReplicators = nil;

        [_storage close];
        _storage = nil;

        _isOpen = NO;

        [[NSNotificationCenter defaultCenter] removeObserver: self];
        [self _clearDocumentCache];
        _modelFactory = nil;
    }
    [_manager _forgetDatabase: self];
}


- (UInt64) totalDataSize {
    NSDirectoryEnumerator* e = [[NSFileManager defaultManager] enumeratorAtPath: _dir];
    UInt64 size = 0;
    while ([e nextObject])
        size += e.fileAttributes.fileSize;
    return size;
}


- (NSString*) privateUUID {
    return [_storage infoForKey: @"privateUUID"];
}

- (NSString*) publicUUID {
    return [_storage infoForKey: @"publicUUID"];
}


- (CBLSymmetricKey*) encryptionKey {
    return [_manager.shared valueForType: @"encryptionKey" name: @"" inDatabaseNamed: _name];
}


#pragma mark - TRANSACTIONS & NOTIFICATIONS:


/** Posts a local NSNotification of a new revision of a document. */
- (void) databaseStorageChanged:(CBLDatabaseChange *)change {
    LogTo(CBLDatabase, @"Added: %@", change.addedRevision);
    if (!_changesToNotify)
        _changesToNotify = [[NSMutableArray alloc] init];
    [_changesToNotify addObject: change];
    if (![self postChangeNotifications]) {
        // The notification wasn't posted yet, probably because a transaction is open.
        // But the CBLDocument, if any, needs to know right away so it can update its
        // currentRevision.
        [[self _cachedDocumentWithID: change.documentID] revisionAdded: change notify: NO];
    }
}

/** Posts a local NSNotification of multiple new revisions. */
- (void) notifyChanges: (NSArray*)changes {
    if (!_changesToNotify)
        _changesToNotify = [[NSMutableArray alloc] init];
    [_changesToNotify addObjectsFromArray: changes];
    [self postChangeNotifications];
}


- (BOOL) postChangeNotifications {
    BOOL posted = NO;
    // This is a 'while' instead of an 'if' because when we finish posting notifications, there
    // might be new ones that have arrived as a result of notification handlers making document
    // changes of their own (the replicator manager will do this.) So we need to check again.
    while (!_storage.inTransaction && _isOpen && !_postingChangeNotifications
            && _changesToNotify.count > 0)
    {
        _postingChangeNotifications = true; // Disallow re-entrant calls
        NSArray* changes = _changesToNotify;
        _changesToNotify = nil;

        if (WillLogTo(CBLDatabase)) {
            NSMutableString* seqs = [NSMutableString string];
            for (CBLDatabaseChange* change in changes) {
                if (seqs.length > 0)
                    [seqs appendString: @", "];
                SequenceNumber seq = [self getRevisionSequence: change.addedRevision];
                if (change.echoed)
                    [seqs appendFormat: @"(%lld)", seq];
                else
                    [seqs appendFormat: @"%lld", seq];
            }
            LogTo(CBLDatabase, @"%@: Posting change notifications: seq %@", self, seqs);
        }
        
        [self postPublicChangeNotification: changes];
        [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseChangesNotification
                                                            object: self
                                                          userInfo: $dict({@"changes", changes})];

        posted = YES;
        _postingChangeNotifications = false;
    }
    return posted;
}


// CBL_StorageDelegate method
- (void) storageExitedTransaction: (BOOL)committed {
    if (!committed) {
        // I already told cached CBLDocuments about these new revisions. Back that out:
        for (CBLDatabaseChange* change in _changesToNotify)
            [[self _cachedDocumentWithID: change.documentID] forgetCurrentRevision];
        _changesToNotify = nil;
    }
    [self postChangeNotifications];
}


- (void) dbChanged: (NSNotification*)n {
    CBLDatabase* senderDB = n.object;
    // Was this posted by a _different_ CBLDatabase instance on the same database as me?
    if (senderDB != self && [senderDB.dir isEqualToString: _dir]) {
        // Careful: I am being called on senderDB's thread, not my own!
        if ([[n name] isEqualToString: CBL_DatabaseChangesNotification]) {
            NSMutableArray* echoedChanges = $marray();
            for (CBLDatabaseChange* change in (n.userInfo)[@"changes"]) {
                if (!change.echoed)
                    [echoedChanges addObject: change.copy]; // copied change is marked as echoed
            }
            if (echoedChanges.count > 0) {
                LogTo(CBLDatabase, @"%@: Notified of %u changes by %@",
                      self, (unsigned)echoedChanges.count, senderDB);
                [self doAsync: ^{
                    [self notifyChanges: echoedChanges];
                }];
            }
        } else if ([[n name] isEqualToString: CBL_DatabaseWillBeDeletedNotification]) {
            [self doAsync: ^{
                LogTo(CBLDatabase, @"%@: Notified of deletion; closing", self);
                [self _close];
            }];
        }
    }
}


#pragma mark - GETTING DOCUMENTS:


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)inRevID
                            options: (CBLContentOptions)options
                             status: (CBLStatus*)outStatus
{
    CBL_MutableRevision* rev = [_storage getDocumentWithID: docID revisionID: inRevID
                                            options: options status: outStatus];
    if (rev && (options & kCBLIncludeAttachments))
        if (![self expandAttachmentsIn: rev options: options status: outStatus])
            rev = nil;
    return rev;
}


#if DEBUG // convenience method for tests
- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)revID
{
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: 0 status: &status];
}
#endif


- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev
                       options: (CBLContentOptions)options
{
    // First check for no-op -- if we just need the default properties and already have them:
    if (options==0 && rev.sequenceIfKnown) {
        NSDictionary* props = rev.properties;
        if (props.cbl_rev && props.cbl_id)
            return kCBLStatusOK;
    }
    Assert(rev.docID && rev.revID);

    CBLStatus status = [_storage loadRevisionBody: rev options: options];

    if (status == kCBLStatusOK)
        if (options & kCBLIncludeAttachments)
            [self expandAttachmentsIn: rev options: options status: &status];
    return status;
}

- (CBL_Revision*) revisionByLoadingBody: (CBL_Revision*)rev
                                options: (CBLContentOptions)options
                                 status: (CBLStatus*)outStatus
{
    // First check for no-op -- if we just need the default properties and already have them:
    if (options==0 && rev.sequenceIfKnown) {
        NSDictionary* props = rev.properties;
        if (props.cbl_rev && props.cbl_id)
            return rev;
    }
    CBL_MutableRevision* nuRev = rev.mutableCopy;
    CBLStatus status = [self loadRevisionBody: nuRev options: options];
    if (outStatus)
        *outStatus = status;
    if (CBLStatusIsError(status))
        nuRev = nil;
    return nuRev;
}


- (SequenceNumber) getRevisionSequence: (CBL_Revision*)rev {
    SequenceNumber sequence = rev.sequenceIfKnown;
    if (sequence <= 0) {
        sequence = [_storage getRevisionSequence: rev];
        if (sequence > 0)
            rev.sequence = sequence;
    }
    return sequence;
}


- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                   options: (const CBLChangesOptions*)options
                                    filter: (CBLFilterBlock)filter
                                    params: (NSDictionary*)filterParams
                                    status: (CBLStatus*)outStatus
{
    CBL_RevisionFilter revFilter = nil;
    if (filter) {
        revFilter = ^BOOL(CBL_Revision* rev) {
            return [self runFilter: filter params: filterParams onRevision: rev];
        };
    }
    return [_storage changesSinceSequence: lastSequence options: options
                                   filter: revFilter status: outStatus];
}

#pragma mark - FILTERS:


- (BOOL) runFilter: (CBLFilterBlock)filter
            params: (NSDictionary*)filterParams
        onRevision: (CBL_Revision*)rev
{
    if (!filter)
        return YES;
    CBLSavedRevision* publicRev = [[CBLSavedRevision alloc] initWithDatabase: self revision: rev];
    @try {
        return filter(publicRev, filterParams);
    } @catch (NSException* x) {
        MYReportException(x, @"filter block");
        return NO;
    }
}


- (id) getDesignDocFunction: (NSString*)fnName
                        key: (NSString*)key
                   language: (NSString**)outLanguage
{
    NSArray* path = [fnName componentsSeparatedByString: @"/"];
    if (path.count != 2)
        return nil;
    CBLStatus status;
    CBL_Revision* rev = [self getDocumentWithID: [@"_design/" stringByAppendingString: path[0]]
                                    revisionID: nil
                                        options: 0
                                         status: &status];
    if (!rev)
        return nil;
    *outLanguage = rev[@"language"] ?: @"javascript";
    NSDictionary* container = $castIf(NSDictionary, rev[key]);
    return container[path[1]];
}


- (CBLFilterBlock) compileFilterNamed: (NSString*)filterName status: (CBLStatus*)outStatus {
    CBLFilterBlock filter = [self filterNamed: filterName];
    if (filter)
        return filter;
    id<CBLFilterCompiler> compiler = [CBLDatabase filterCompiler];
    if (!compiler) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    NSString* language;
    NSString* source = $castIf(NSString, [self getDesignDocFunction: filterName
                                                                key: @"filters"
                                                           language: &language]);
    if (!source) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }

    filter = [compiler compileFilterFunction: source language: language];
    if (!filter) {
        Warn(@"Filter %@ failed to compile", filterName);
        *outStatus = kCBLStatusCallbackError;
        return nil;
    }
    [self setFilterNamed: filterName asBlock: filter];
    return filter;
}


#pragma mark - VIEWS:
// Note: Public view methods like -viewNamed: are in CBLDatabase.m.


- (NSArray*) allViews {
    return [_storage.allViewNames my_map: ^id(NSString* viewName) {
        return [self existingViewNamed: viewName];
    }];
}


- (void) forgetViewNamed: (NSString*)name {
    [_views removeObjectForKey: name];
}


- (CBLView*) makeAnonymousView {
    for (;;) {
        NSString* name = $sprintf(@"$anon$%lx", random());
        if (![self existingViewNamed: name])
            return [self viewNamed: name];
    }
}


- (CBLQueryIteratorBlock) getAllDocs: (CBLQueryOptions*)options
                              status: (CBLStatus*)outStatus
{
    return [_storage getAllDocs: options status: outStatus];
}


- (void) postNotification: (NSNotification*)notification {
    [self doAsync:^{
        [[NSNotificationCenter defaultCenter] postNotification: notification];
    }];
}

- (BOOL) saveLocalUUIDInLocalCheckpointDocument: (NSError**)outError {
    return [self putLocalCheckpointDocumentWithKey: kCBLDatabaseLocalCheckpoint_LocalUUID
                                             value: self.privateUUID
                                          outError: outError];
}

- (BOOL) putLocalCheckpointDocumentWithKey: (NSString*)key
                                     value:(id)value
                                  outError: (NSError**)outError {
    if (key == nil || value == nil)
        return NO;

    NSMutableDictionary* document = [NSMutableDictionary dictionaryWithDictionary:
                                        [self getLocalCheckpointDocument]];
    document[key] = value;
    BOOL result = [self putLocalDocument: document withID: kLocalCheckpointDocId error: outError];
    if (!result)
        Warn(@"CBLDatabase: Could not create a local checkpoint document with an error: %@", *outError);
    return result;
}


- (NSDictionary*) getLocalCheckpointDocument {
    return [self existingLocalDocumentWithID: kLocalCheckpointDocId];
}


- (id) getLocalCheckpointDocumentPropertyValueForKey: (NSString*)key {
    return [[self getLocalCheckpointDocument] objectForKey: key];
}


// CBL_StorageDelegate method. It has to be in this category but the real method is in another one
- (NSString*) generateRevIDForJSON: (NSData*)json
                           deleted: (BOOL)deleted
                         prevRevID: (NSString*)prevID
{
    return [self _generateRevIDForJSON: json deleted: deleted prevRevID: prevID];
}

@end
