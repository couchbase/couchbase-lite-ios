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
#import "CBLDatabase+REST.h"
#import "CBL_ForestDBStorage.h"
#import "CBL_SQLiteStorage.h"
#import "CBLInternal.h"
#import "CBLModel_Internal.h"
#import "CBL_Revision.h"
#import "CBLDatabaseChange.h"
#import "CBL_BlobStore.h"
#import "CBL_Replicator.h"
#import "CBL_Shared.h"
#import "CBLMisc.h"
#import "CBLDatabase.h"
#import "CBLDatabaseUpgrade.h"
#import "CBLSymmetricKey.h"
#import "CBLCookieStorage.h"
#import "CouchbaseLitePrivate.h"

#import "MYBlockUtils.h"
#import "ExceptionUtils.h"


DefineLogDomain(Database);


NSString* const CBL_DatabaseChangesNotification = @"CBLDatabaseChanges";
NSString* const CBL_DatabaseWillCloseNotification = @"CBL_DatabaseWillClose";
NSString* const CBL_DatabaseWillBeDeletedNotification = @"CBL_DatabaseWillBeDeleted";

NSString* const CBL_PrivateRunloopMode = @"CouchbaseLitePrivate";
NSArray* CBL_RunloopModes;

const CBLChangesOptions kDefaultCBLChangesOptions = {UINT_MAX, NO, NO, YES, NO};

// When this many changes pile up in _changesToNotify, start removing their bodies to save RAM
#define kManyChangesToNotify 5000

// How long to wait after a database opens before expiring docs
#define kHousekeepingDelayAfterOpening 3.0


static BOOL sAutoCompact = YES;


@implementation CBLDatabase (Internal)

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
    return [self openWithOptions: [_manager defaultOptionsForDatabaseNamed: _name]
                           error: outError];
}

- (BOOL) openWithOptions: (CBLDatabaseOptions*)options error: (NSError**)outError {
    if (_isOpen)
        return YES;
    LogTo(Database, @"Opening %@", self);

    // Create the database directory:
    _readOnly = _readOnly || options.readOnly;
    if (!_readOnly && ![[NSFileManager defaultManager] createDirectoryAtPath: _dir
                                                 withIntermediateDirectories: YES
                                                                  attributes: nil
                                                                       error: outError])
        return NO;

    // Instantiate storage:
    NSString* storageType = options.storageType ?: (_manager.storageType ?: kCBLSQLiteStorage);
    NSString* storageClassName = $sprintf(@"CBL_%@Storage", storageType);
    Class primaryStorage = NSClassFromString(storageClassName);
    if (!primaryStorage) {
        if ($equal(storageType, kCBLSQLiteStorage) || $equal(storageType, kCBLForestDBStorage))
            Warn(@"storageType is '%@' but no %@ class found;"
                 " make sure `-ObjC` is in Other Linker Flags in Build Settings",
                 storageType, storageClassName);
    } else if (![primaryStorage conformsToProtocol: @protocol(CBL_Storage)]) {
        primaryStorage = nil;
    }
    if (!primaryStorage)
        return CBLStatusToOutNSError(kCBLStatusInvalidStorageType, outError);
    BOOL primarySQLite = [storageType isEqualToString: kCBLSQLiteStorage];
    Class otherStorage = NSClassFromString(primarySQLite ? @"CBL_ForestDBStorage"
                                                         : @"CBL_SQLiteStorage");

    BOOL upgrade = NO;

    if (options.storageType) {
        // If explicit storage type given in options, always use primary storage type,
        // and if secondary db exists, try to upgrade from it:
        upgrade = [otherStorage databaseExistsIn: _dir] && ![primaryStorage databaseExistsIn: _dir];
        if (upgrade) {
            if (_readOnly)
                return CBLStatusToOutNSError(kCBLStatusForbidden, outError);
            if (primarySQLite)  // can't upgrade to SQLite
                return CBLStatusToOutNSError(kCBLStatusInvalidStorageType, outError);
        }
    } else {
        // If options don't specify, use primary unless secondary db already exists in dir:
        if (otherStorage && [otherStorage databaseExistsIn: _dir])
            primaryStorage = otherStorage;
    }

    LogTo(Database, @"Using %@ for db at %@; upgrade=%d", primaryStorage, _dir, upgrade);

    _storage = [[primaryStorage alloc] init];
    _storage.delegate = self;
    _storage.autoCompact = sAutoCompact;

    // Encryption:
    CBLSymmetricKey* encryptionKey = nil;
    id keyOrPass = options.encryptionKey;
    if (keyOrPass) {
#if !TARGET_OS_IPHONE
        if ([keyOrPass isEqual: @YES]) {
            encryptionKey = [self encryptionKeyFromKeychain: outError];
            if (!encryptionKey)
                return NO;
        } else
#endif
        {
            encryptionKey = [[CBLSymmetricKey alloc] initWithKeyOrPassword: keyOrPass];
        }
        options.encryptionKey = encryptionKey;
        if ([_storage respondsToSelector: @selector(setEncryptionKey:)])
            [_storage setEncryptionKey: encryptionKey];
    }

    // Open the storage!
    if (![_storage openInDirectory: _dir
                          readOnly: _readOnly
                           manager: _manager
                             error: outError])
        return NO;

    // First-time setup:
    if (!self.privateUUID) {
        [_storage setInfo: CBLCreateUUID() forKey: @"privateUUID"];
        [_storage setInfo: CBLCreateUUID() forKey: @"publicUUID"];
    }

    unsigned maxRevs = [[_storage infoForKey: @"max_revs"] intValue];
    if (!maxRevs)
        maxRevs = (unsigned)_manager.defaultMaxRevTreeDepth;
    _storage.maxRevTreeDepth = maxRevs;

    // Open attachment store:
    NSString* attachmentsPath = self.attachmentStorePath;
    _attachments = [[CBL_BlobStore alloc] initWithPath: attachmentsPath
                                         encryptionKey: encryptionKey
                                                 error: outError];
    if (!_attachments) {
        Warn(@"%@: Couldn't open attachment store at %@", self, attachmentsPath);
        [_storage close];
        _storage = nil;
        return NO;
    }

    [self willChangeValueForKey: @"isOpen"];
    _isOpen = YES;
    [self didChangeValueForKey: @"isOpen"];

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

#if TARGET_OS_IPHONE
    // On iOS, observe low-memory notifications:
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(lowMemory:)
                                                 name: UIApplicationDidReceiveMemoryWarningNotification
                                               object: nil];
#endif

    if (upgrade) {
        // Upgrading a SQLite database:
        Class databaseUpgradeClass = NSClassFromString(@"CBLDatabaseUpgrade");
        if (databaseUpgradeClass) {
            NSString* dbPath = [_dir stringByAppendingPathComponent: @"db.sqlite3"];
            Log(@"%@: Upgrading to %@ ...", self, storageType);
            CBLDatabaseUpgrade* upgrader = [[databaseUpgradeClass alloc] initWithDatabase: self
                                                                               sqliteFile: dbPath];
            CBLStatus status = [upgrader import];
            if (CBLStatusIsError(status)) {
                Warn(@"Upgrade failed: status %d", status);
                [upgrader backOut];
                [self _close];
                return CBLStatusToOutNSError(status, outError);
            } else {
                [upgrader deleteSQLiteFiles];
            }
        } else {
            Warn(@"Upgrade skipped: Database upgrading class is not present.");
        }
    }

    [self scheduleDocumentExpiration: kHousekeepingDelayAfterOpening];

    return YES;
}


#if !TARGET_OS_IPHONE
- (CBLSymmetricKey*) encryptionKeyFromKeychain: (NSError**)outError {
    NSString* dir = _manager.directory.stringByAbbreviatingWithTildeInPath;
    NSString* itemName = $sprintf(@"%@ database in %@", self.name, dir);
    NSError* error;
    CBLSymmetricKey* key = [[CBLSymmetricKey alloc] initWithKeychainItemNamed: itemName
                                                                        error: &error];
    if (!key) {
        if (error.code == errSecItemNotFound) {
            key = [CBLSymmetricKey new];
            if (![key saveKeychainItemNamed: itemName error: outError])
                key = nil;
        } else {
            if (outError) *outError = error;
        }
    }
    return key;
}
#endif


- (void) _close {
    if (_isOpen) {
        LogTo(Database, @"Closing <%p> %@", self, _dir);
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
        for (id<CBL_Replicator> repl in _activeReplicators.copy)
            [repl databaseClosing];
        
        _activeReplicators = nil;

        [_storage close];
        _storage = nil;
        _attachments = nil;

        [self willChangeValueForKey: @"isOpen"];
        _isOpen = NO;
        [self didChangeValueForKey: @"isOpen"];

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


#pragma mark - EXPIRATION:


- (void) setExpirationDate: (NSDate*)date ofDocument: (NSString*)documentID {
    UInt64 timestamp = date ? (UInt64)date.timeIntervalSince1970 : 0;
    [_storage setExpiration: timestamp ofDocument: documentID];
    [self scheduleDocumentExpiration: 0.0];
}


- (void) scheduleDocumentExpiration: (NSTimeInterval)minimumDelay {
    [NSObject cancelPreviousPerformRequestsWithTarget: self
                                             selector: @selector(purgeExpiredDocuments)
                                               object: nil];
    UInt64 nextExpiration = _storage.nextDocumentExpiry;
    if (nextExpiration > 0) {
        NSDate* expDate = [NSDate dateWithTimeIntervalSince1970: nextExpiration];
        NSTimeInterval delay = MAX(expDate.timeIntervalSinceNow + 1.0, minimumDelay);
        LogTo(Database, @"Scheduling next doc expiration in %.3g sec", delay);
        dispatch_async(dispatch_get_main_queue(), ^{
            // Schedule the perform on the main thread, because we know it has a runloop
            [self performSelector: @selector(purgeExpiredDocuments)
                       withObject: nil
                       afterDelay: delay];
        });
    } else {
        LogTo(Database, @"No pending doc expirations");
    }
}

- (void) purgeExpiredDocuments {
    // Careful: This is called on the main thread
    [self doAsync:^{
        LogTo(Database, @"Purging expired documents...");
        NSUInteger nPurged = [_storage purgeExpiredDocuments];
        LogTo(Database, @"Purged %lu expired documents", (unsigned long)nPurged);
        [self scheduleDocumentExpiration: 1.0];
    }];
}


#pragma mark - TRANSACTIONS & NOTIFICATIONS:


/** Posts a local NSNotification of a new revision of a document. */
- (void) databaseStorageChanged:(CBLDatabaseChange *)change {
    LogTo(Database, @"---> Added: %@ as seq %lld",
          change.addedRevision, change.addedRevision.sequence);
    if (!_changesToNotify)
        _changesToNotify = [[NSMutableArray alloc] init];
    [_changesToNotify addObject: change];
    if (![self postChangeNotifications]) {
        // The notification wasn't posted yet, probably because a transaction is open.
        // But the CBLDocument, if any, needs to know right away so it can update its
        // currentRevision.
        [[self _cachedDocumentWithID: change.documentID] revisionAdded: change notify: NO];
    }

    // Squish the change objects if too many of them are piling up:
    if (_changesToNotify.count >= kManyChangesToNotify) {
        if (_changesToNotify.count == kManyChangesToNotify) {
            for (CBLDatabaseChange* c in _changesToNotify)
                [c reduceMemoryUsage];
        } else {
            [change reduceMemoryUsage];
        }
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

        if (WillLogTo(Database)) {
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
            LogVerbose(Database, @"%@: Posting change notifications: seq %@", self, seqs);
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
                LogVerbose(Database, @"%@: Notified of %u changes by %@",
                           self, (unsigned)echoedChanges.count, senderDB);
                [self doAsync: ^{
                    [self notifyChanges: echoedChanges];
                }];
            }
        } else if ([[n name] isEqualToString: CBL_DatabaseWillBeDeletedNotification]) {
            [self doAsync: ^{
                LogTo(Database, @"%@: Notified of deletion; closing", self);
                [self _close];
            }];
        }
    }
}


#if TARGET_OS_IPHONE
- (void) lowMemory: (NSNotification*)n {
    [self doAsync: ^{
        [self _pruneDocumentCache];
        if ([_storage respondsToSelector:@selector(lowMemoryWarning)])
            [_storage lowMemoryWarning];
    }];
}
#endif


#pragma mark - GETTING DOCUMENTS:


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (CBL_RevID*)inRevID
                           withBody: (BOOL)withBody
                             status: (CBLStatus*)outStatus
{
    return [_storage getDocumentWithID: docID revisionID: inRevID
                              withBody: withBody status: outStatus];
}


#if DEBUG // convenience method for tests
- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (CBL_RevID*)revID
{
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID withBody: YES status: &status];
}
#endif


- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev {
    // First check whether we already have the body (or know it's missing) and the sequence:
    if (rev.sequenceIfKnown) {
        if (rev.body)
            return kCBLStatusOK;
        else if (rev.missing)
            return kCBLStatusNotFound;
    }
    Assert(rev.docID && rev.revID);

    return [_storage loadRevisionBody: rev];
}

- (CBL_Revision*) revisionByLoadingBody: (CBL_Revision*)rev
                                 status: (CBLStatus*)outStatus
{
    // First check whether we already have the body (or know it's missing) and the sequence:
    if (rev.sequenceIfKnown) {
        if (rev.body) {
            *outStatus = kCBLStatusOK;
            return rev;
        } else if (rev.missing) {
            *outStatus = kCBLStatusNotFound;
            return nil;
        }
    }
    Assert(rev.docID && rev.revID);

    CBL_MutableRevision* nuRev = rev.mutableCopy;
    *outStatus = [_storage loadRevisionBody: nuRev];
    if (CBLStatusIsError(*outStatus))
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


// Used by new replicator
- (NSArray*) getPossibleAncestorsOfDocID: (NSString*)docID
                                   revID: (CBL_RevID*)revID
                                   limit: (NSUInteger)limit
{
    CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: docID revID: revID deleted: NO];
    if ([_storage getRevisionSequence: rev] > 0)
        return @[revID];  // Already have it!
    return [_storage getPossibleAncestorRevisionIDs: rev
                                              limit: (unsigned)limit
                                         haveBodies: NULL];
}


#pragma mark - HISTORY:


- (NSArray<CBL_RevID*>*) getRevisionHistory: (CBL_Revision*)rev
                               backToRevIDs: (NSArray<CBL_RevID*>*)ancestorRevIDs
{
    AssertContainsRevIDs(ancestorRevIDs);
    NSSet* ancestors = ancestorRevIDs ? [[NSSet alloc] initWithArray: ancestorRevIDs] : nil;
    return [_storage getRevisionHistory: rev backToRevIDs: ancestors];
}


#pragma mark - FILTERS:


- (CBLFilterBlock) loadFilterNamed: (NSString*)filterName status: (CBLStatus*)outStatus {
    CBLFilterBlock filter = [self filterNamed: filterName];
    //
    if (!filter && [self respondsToSelector: @selector(compileFilterNamed:status:)]) {
        CBLStatus status;
        filter = [self compileFilterNamed: filterName status: &status];
        [self setFilterNamed: filterName asBlock: filter];
    }
    return filter;
}


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


static SequenceNumber keyToSequence(id key, SequenceNumber dflt) {
    return [key isKindOfClass: [NSNumber class]]? [key longLongValue] : dflt;
}


- (CBLQueryEnumerator*) getAllDocs: (CBLQueryOptions*)options
                            status: (CBLStatus*)outStatus
{
    if (!options)
        options = [CBLQueryOptions new];
    else if (options.isEmpty)
        return [[CBLQueryEnumerator alloc] initWithDatabase: self
                                                       view: nil
                                             sequenceNumber: self.lastSequenceNumber
                                                       rows: nil];

    // For regular all-docs, let storage do it all:
    if (options->allDocsMode != kCBLBySequence) {
        CBLQueryEnumerator* e = [_storage getAllDocs: options status: outStatus];
        [e setDatabase: self view: nil];
        return e;
    }

    // For changes feed mode (kCBLBySequence) do more work here:
    SequenceNumber lastSeq = _storage.lastSequence;
    SequenceNumber minSeq = keyToSequence(options.minKey, 1);
    SequenceNumber maxSeq = keyToSequence(options.maxKey, INT64_MAX);
    if (!(options->descending ? options->inclusiveEnd : options->inclusiveStart))
        ++minSeq;
    if (!(options->descending ? options->inclusiveStart : options->inclusiveEnd))
        --maxSeq;
    if (minSeq > maxSeq || minSeq > lastSeq) {
        // Empty result:
        *outStatus = kCBLStatusOK;
        return [[CBLQueryEnumerator alloc] initWithDatabase: self
                                                       view: nil
                                             sequenceNumber: lastSeq
                                                       rows: nil];
    }

    CBLChangesOptions changesOpts = {
        .limit = options->limit,
        .includeDocs = options->includeDocs,
        .includeConflicts = YES,
        .sortBySequence = YES
    };
    CBL_RevisionList* revs = [_storage changesSinceSequence: minSeq - 1
                                                    options: &changesOpts
                                                     filter: nil
                                                     status: outStatus];
    if (!revs)
        return nil;

    NSMutableArray* result = [NSMutableArray arrayWithCapacity: revs.count];
    NSEnumerator* revEnum = (options->descending) ? revs.allRevisions.reverseObjectEnumerator
                                                  : revs.allRevisions.objectEnumerator;
    for (CBL_Revision* rev in revEnum) {
        SequenceNumber seq = rev.sequence;
        if (seq > maxSeq) {
            if (options->descending)
                continue;
            else
                break;
        }
        NSDictionary* value = $dict({@"rev", rev.revIDString},
                                    {@"deleted", (rev.deleted ?$true : nil)});
        CBLQueryRow* row =  [[CBLQueryRow alloc] initWithDocID: rev.docID
                                                      sequence: seq
                                                           key: rev.docID
                                                         value: value
                                                   docRevision: rev];
        if (options.filter) {
            [row moveToDatabase: self view: nil];
            if (!options.filter(row))
                continue;
        }
        [result addObject: row];
    }

    return [[CBLQueryEnumerator alloc] initWithDatabase: self
                                                   view: nil
                                         sequenceNumber: lastSeq
                                                   rows: result];
}


- (void) postNotification: (NSNotification*)notification {
    [self doAsync:^{
        [[NSNotificationCenter defaultCenter] postNotification: notification];
    }];
}


#pragma mark - Cookie Storage:


- (CBLCookieStorage*) cookieStorage {
    CBLCookieStorage* cookieStorage = _cookieStorage;
    if (!cookieStorage) {
        cookieStorage = [[CBLCookieStorage alloc] initWithDB: self];
        _cookieStorage = cookieStorage;
    }
    return cookieStorage;
}

@end
