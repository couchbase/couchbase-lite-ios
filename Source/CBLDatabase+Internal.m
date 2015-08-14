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
#import "CBL_Replicator.h"
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

const CBLChangesOptions kDefaultCBLChangesOptions = {UINT_MAX, NO, NO, YES, NO};

// When this many changes pile up in _changesToNotify, start removing their bodies to save RAM
#define kManyChangesToNotify 5000

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
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(dbChanged:)
                                                 name: CBL_DatabaseWillCloseNotification
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
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: CBL_DatabaseWillCloseNotification
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
        } else if ([[n name] isEqualToString: CBL_DatabaseWillCloseNotification]) {
            [self doAsync: ^{
                LogTo(CBLDatabase, @"%@: Notified of closing", self);
                [self _close];
            }];
        }
    }
}


#pragma mark - GETTING DOCUMENTS:


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)inRevID
                           withBody: (BOOL)withBody
                             status: (CBLStatus*)outStatus
{
    return [_storage getDocumentWithID: docID revisionID: inRevID
                              withBody: withBody status: outStatus];
}


#if DEBUG // convenience method for tests
- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)revID
{
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID withBody: YES status: &status];
}
#endif


- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev {
    // First check for no-op -- if we just need the default properties and already have them:
    if (rev.sequenceIfKnown) {
        NSDictionary* props = rev.properties;
        if (props.cbl_rev && props.cbl_id)
            return kCBLStatusOK;
    }
    Assert(rev.docID && rev.revID);

    return [_storage loadRevisionBody: rev];
}

- (CBL_Revision*) revisionByLoadingBody: (CBL_Revision*)rev
                                 status: (CBLStatus*)outStatus
{
    // First check for no-op -- if we just need the default properties and already have them:
    if (rev.sequenceIfKnown) {
        NSDictionary* props = rev.properties;
        if (props.cbl_rev && props.cbl_id) {
            if (outStatus)
                *outStatus = kCBLStatusOK;
            return rev;
        }
    }
    CBL_MutableRevision* nuRev = rev.mutableCopy;
    CBLStatus status = [self loadRevisionBody: nuRev];
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


// Used by new replicator
- (NSArray*) getPossibleAncestorsOfDocID: (NSString*)docID
                                   revID: (NSString*)revID
                                   limit: (NSUInteger)limit
{
    CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: docID revID: revID deleted: NO];
    if ([_storage getRevisionSequence: rev] > 0)
        return @[revID];  // Already have it!
    return [_storage getPossibleAncestorRevisionIDs: rev
                                              limit: (unsigned)limit
                                    onlyAttachments: NO];
}


#pragma mark - HISTORY:


- (NSArray*) getRevisionHistory: (CBL_Revision*)rev
                   backToRevIDs: (NSArray*)ancestorRevIDs
{
    NSSet* ancestors = ancestorRevIDs ? [[NSSet alloc] initWithArray: ancestorRevIDs] : nil;
    return [_storage getRevisionHistory: rev backToRevIDs: ancestors];
}

/** Turns an array of CBL_Revisions into a _revisions dictionary, as returned by the REST API's 
    ?revs=true option. */
+ (NSDictionary*) makeRevisionHistoryDict: (NSArray*)history {
    if (!history)
        return nil;

    // Try to extract descending numeric prefixes:
    NSMutableArray* suffixes = $marray();
    id start = nil;
    int lastRevNo = -1;
    for (CBL_Revision* rev in history) {
        int revNo;
        NSString* suffix;
        if ([CBL_Revision parseRevID: rev.revID intoGeneration: &revNo andSuffix: &suffix]) {
            if (!start)
                start = @(revNo);
            else if (revNo != lastRevNo - 1) {
                start = nil;
                break;
            }
            lastRevNo = revNo;
            [suffixes addObject: suffix];
        } else {
            start = nil;
            break;
        }
    }

    NSArray* revIDs = start ? suffixes : [history my_map: ^(id rev) {return [rev revID];}];
    return $dict({@"ids", revIDs}, {@"start", start});
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
                                       withBody: YES
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


static SequenceNumber keyToSequence(id key, SequenceNumber dflt) {
    return [key isKindOfClass: [NSNumber class]]? [key longLongValue] : dflt;
}


- (CBLQueryIteratorBlock) getAllDocs: (CBLQueryOptions*)options
                              status: (CBLStatus*)outStatus
{
    // For regular all-docs, let storage do it all:
    if (!options || options->allDocsMode != kCBLBySequence)
        return [_storage getAllDocs: options status: outStatus];

    // For changes feed mode (kCBLBySequence) do more work here:
    if (options->descending) {
        *outStatus = kCBLStatusNotImplemented;    //FIX: Implement descending order
        return nil;
    }
    CBLChangesOptions changesOpts = {
        .limit = options->limit,
        .includeDocs = options->includeDocs,
        .includeConflicts = YES,
        .sortBySequence = YES
    };
    SequenceNumber startSeq = keyToSequence(options.startKey, 1);
    SequenceNumber endSeq = keyToSequence(options.endKey, INT64_MAX);
    if (!options->inclusiveStart)
        ++startSeq;
    if (!options->inclusiveEnd)
        --endSeq;
    SequenceNumber minSeq = startSeq, maxSeq = endSeq;
    if (minSeq > maxSeq) {
        *outStatus = kCBLStatusOK;
        return nil;  // empty result
    }
    CBL_RevisionList* revs = [_storage changesSinceSequence: minSeq - 1
                                                    options: &changesOpts
                                                     filter: nil
                                                     status: outStatus];
    if (!revs)
        return nil;

    NSEnumerator* revEnum = (options->descending) ? revs.allRevisions.reverseObjectEnumerator
                                                  : revs.allRevisions.objectEnumerator;
    return ^CBLQueryRow*() {
        for (;;) {
            CBL_Revision* rev = revEnum.nextObject;
            if (!rev)
                return nil;
            SequenceNumber seq = rev.sequence;
            if (seq < minSeq || seq > maxSeq)
                return nil;
            NSDictionary* value = $dict({@"rev", rev.revID},
                                        {@"deleted", (rev.deleted ?$true : nil)});
            CBLQueryRow* row =  [[CBLQueryRow alloc] initWithDocID: rev.docID
                                                          sequence: seq
                                                               key: rev.docID
                                                             value: value
                                                       docRevision: rev
                                                           storage: nil];
            if (!options.filter)
                return row;
            row.database = self;
            if (options.filter(row)) {
                //row.database = nil;
                return row;
            }
        }
    };
}


- (void) postNotification: (NSNotification*)notification {
    [self doAsync:^{
        [[NSNotificationCenter defaultCenter] postNotification: notification];
    }];
}


// CBL_StorageDelegate method. It has to be in this category but the real method is in another one
- (NSString*) generateRevIDForJSON: (NSData*)json
                           deleted: (BOOL)deleted
                         prevRevID: (NSString*)prevID
{
    return [self _generateRevIDForJSON: json deleted: deleted prevRevID: prevID];
}

@end
