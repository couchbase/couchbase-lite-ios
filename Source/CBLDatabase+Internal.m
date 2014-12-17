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

#import <CBForest/CBForest.hh>

extern "C" {
#import "CBLDatabase+Internal.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase+LocalDocs.h"
#import "CBLInternal.h"
#import "CBLModel_Internal.h"
#import "CBL_Revision.h"
#import "CBLDatabaseChange.h"
#import "CBLCollateJSON.h"
#import "CBL_BlobStore.h"
#import "CBL_Puller.h"
#import "CBL_Pusher.h"
#import "CBL_Shared.h"
#import "CBLMisc.h"
#import "CBLDatabase.h"
#import "CouchbaseLitePrivate.h"

#import "MYBlockUtils.h"
#import "ExceptionUtils.h"
}

#import <CBForest/CBForest.hh>
#import "CBLForestBridge.h"

using namespace forestdb;


// Size of ForestDB buffer cache allocated for a database
#define kDBBufferCacheSize (8*1024*1024)

// How often ForestDB should check whether databases need auto-compaction
#define kAutoCompactInterval (5*60.0)

static NSTimeInterval sAutoCompactInterval = kAutoCompactInterval;

NSString* const CBL_DatabaseChangesNotification = @"CBLDatabaseChanges";
NSString* const CBL_DatabaseWillCloseNotification = @"CBL_DatabaseWillClose";
NSString* const CBL_DatabaseWillBeDeletedNotification = @"CBL_DatabaseWillBeDeleted";

NSString* const CBL_PrivateRunloopMode = @"CouchbaseLitePrivate";
NSArray* CBL_RunloopModes;


@implementation CBLDatabase (Internal)


static void FDBLogCallback(forestdb::logLevel level, const char *message) {
    switch (level) {
        case forestdb::kDebug:
            LogTo(CBLDatabaseVerbose, @"ForestDB: %s", message);
            break;
        case forestdb::kInfo:
            LogTo(CBLDatabase, @"ForestDB: %s", message);
            break;
        case forestdb::kWarning:
            Warn(@"%s", message);
        case forestdb::kError:
            Warn(@"ForestDB error: %s", message);
        default:
            break;
    }
}


+ (void) initialize {
    if (self == [CBLDatabase class]) {
        CBL_RunloopModes = @[NSRunLoopCommonModes, CBL_PrivateRunloopMode];

        [self setAutoCompact: YES];

        forestdb::LogCallback = FDBLogCallback;
        if (WillLogTo(CBLDatabaseVerbose))
            forestdb::LogLevel = kDebug;
        else if (WillLogTo(CBLDatabase))
            forestdb::LogLevel = kInfo;
    }
}


- (Database*) forestDB {
    return _forest;
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
    sAutoCompactInterval = autoCompact ? kAutoCompactInterval : 0.0;
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

    // Open the ForestDB database:
    NSString* forestPath = [_dir stringByAppendingPathComponent: @"db.forest"];
    Database::openFlags options = _readOnly ? FDB_OPEN_FLAG_RDONLY : FDB_OPEN_FLAG_CREATE;

    Database::config config = Database::defaultConfig();
    config.buffercache_size = kDBBufferCacheSize;
    config.wal_threshold = 4096;
    config.wal_flush_before_commit = true;
    config.seqtree_opt = true;
    config.compress_document_body = true;
    if (sAutoCompactInterval > 0) {
        config.compactor_sleep_duration = (uint64_t)sAutoCompactInterval;
    } else {
        config.compaction_threshold = 0; // disables auto-compact
    }

    try {
        _forest = new Database(std::string(forestPath.UTF8String), options, config);
    } catch (forestdb::error err) {
        if (outError)
            *outError = CBLStatusToNSError(CBLStatusFromForestDBStatus(err.status), nil);
        return NO;
    } catch (...) {
        if (outError)
            *outError = CBLStatusToNSError(kCBLStatusException, nil);
        return NO;
    }

    // First-time setup:
    if (!self.privateUUID) {
        [self setInfo: CBLCreateUUID() forKey: @"privateUUID"];
        [self setInfo: CBLCreateUUID() forKey: @"publicUUID"];
    }

    // Open attachment store:
    NSString* attachmentsPath = self.attachmentStorePath;
    _attachments = [[CBL_BlobStore alloc] initWithPath: attachmentsPath error: outError];
    if (!_attachments) {
        Warn(@"%@: Couldn't open attachment store at %@", self, attachmentsPath);
        delete _forest;
        _forest = nil;
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
        Assert(_transactionLevel == 0, @"Can't close database while %u transactions active",
                _transactionLevel);

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
            [view databaseClosing];
        
        _views = nil;
        for (CBL_Replicator* repl in _activeReplicators.copy)
            [repl databaseClosing];
        
        _activeReplicators = nil;

        delete _forest;
        _forest = NULL;

        _isOpen = NO;
        _transactionLevel = 0;

        [[NSNotificationCenter defaultCenter] removeObserver: self];
        [self _clearDocumentCache];
        _modelFactory = nil;
    }
    [_manager _forgetDatabase: self];
}


- (NSUInteger) _documentCount {
    auto opts = DocEnumerator::Options::kDefault;
    opts.contentOptions = Database::kMetaOnly;

    NSUInteger count = 0;
    for (DocEnumerator e(*_forest, forestdb::slice::null, forestdb::slice::null, opts); e.next(); ) {
        VersionedDocument vdoc(*_forest, *e);
        if (!vdoc.isDeleted())
            ++count;
    }
    return count;
}


- (SequenceNumber) _lastSequence {
    return _forest->lastSequence();
}


- (UInt64) totalDataSize {
    NSDirectoryEnumerator* e = [[NSFileManager defaultManager] enumeratorAtPath: _dir];
    UInt64 size = 0;
    while ([e nextObject])
        size += e.fileAttributes.fileSize;
    return size;
}


- (NSString*) privateUUID {
    return [self infoForKey: @"privateUUID"];
}

- (NSString*) publicUUID {
    return [self infoForKey: @"publicUUID"];
}


- (BOOL) _compact: (NSError**)outError {
    CBLStatus status = [self _try: ^{
        _forest->compact();
        return kCBLStatusOK;
    }];
    if (CBLStatusIsError(status)) {
        if (outError)
            *outError = CBLStatusToNSError(status, nil);
        return NO;
    }
    return YES;
}


#pragma mark - TRANSACTIONS & NOTIFICATIONS:


- (CBLStatus) _try: (CBLStatus(^)())block {
    try {
        return block();
    } catch (forestdb::error err) {
        return CBLStatusFromForestDBStatus(err.status);
    } catch (...) {
        return kCBLStatusException;
    }
}


- (CBLStatus) _withVersionedDoc: (NSString*)docID
                             do: (CBLStatus(^)(VersionedDocument&))block
{
    try {
        VersionedDocument doc(*_forest, docID);
        if (!doc.exists())
            return kCBLStatusNotFound;
        return block(doc);
    } catch (forestdb::error err) {
        return CBLStatusFromForestDBStatus(err.status);
    } catch (...) {
        return kCBLStatusException;
    }
}


- (CBLStatus) _inTransaction: (CBLStatus(^)())block {
    LogTo(CBLDatabase, @"BEGIN transaction...");
    if (++_transactionLevel == 1) {
        _forestTransaction = new Transaction(_forest);
    }

    CBLStatus status = [self _try: ^CBLStatus{
        return block();
    }];

    LogTo(CBLDatabase, @"END transaction (status=%d)", status);
    if (--_transactionLevel == 0) {
        delete _forestTransaction;
        _forestTransaction = NULL;
        [self postChangeNotifications];
    }
    return status;
}


/** Posts a local NSNotification of a new revision of a document. */
- (void) notifyChange: (CBLDatabaseChange*)change {
    LogTo(CBLDatabase, @"Added: %@", change.addedRevision);
    if (!_changesToNotify)
        _changesToNotify = [[NSMutableArray alloc] init];
    [_changesToNotify addObject: change];
    [self postChangeNotifications];
}

/** Posts a local NSNotification of multiple new revisions. */
- (void) notifyChanges: (NSArray*)changes {
    if (!_changesToNotify)
        _changesToNotify = [[NSMutableArray alloc] init];
    [_changesToNotify addObjectsFromArray: changes];
    [self postChangeNotifications];
}


- (void) postChangeNotifications {
    // This is a 'while' instead of an 'if' because when we finish posting notifications, there
    // might be new ones that have arrived as a result of notification handlers making document
    // changes of their own (the replicator manager will do this.) So we need to check again.
    while (_transactionLevel == 0 && _isOpen && !_postingChangeNotifications
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

        _postingChangeNotifications = false;
    }
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
    __block CBL_MutableRevision* result = nil;
    *outStatus = [self _withVersionedDoc: docID do: ^(VersionedDocument& doc) {
#if DEBUG
        LogTo(CBLDatabase, @"Read %s", doc.dump().c_str());
#endif
        NSString* revID = inRevID;
        if (revID == nil) {
            const Revision* rev = doc.currentRevision();
            if (!rev || rev->isDeleted())
                return kCBLStatusDeleted;
            revID = (NSString*)rev->revID;
        }

        result = [CBLForestBridge revisionObjectFromForestDoc: doc
                                                        revID: revID
                                                      options: options];
        if (!result)
            return kCBLStatusNotFound;
        if (options & kCBLIncludeAttachments)
            [self expandAttachmentsIn: result options: options];
        return kCBLStatusOK;
    }];
    return result;
}


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                           sequence: (SequenceNumber)sequence
                             status: (CBLStatus*)outStatus
{
    __block CBL_MutableRevision* result = nil;
    *outStatus = [self _withVersionedDoc: docID do: ^(VersionedDocument& doc) {
#if DEBUG
        LogTo(CBLDatabase, @"Read %s", doc.dump().c_str());
#endif
        result = [CBLForestBridge revisionObjectFromForestDoc: doc
                                                     sequence: sequence
                                                      options: 0];
        return result ? kCBLStatusOK : kCBLStatusNotFound;
    }];
    return result;
}


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)revID
{
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: 0 status: &status];
}


- (BOOL) existsDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: kCBLNoBody status: &status] != nil;
}


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

    return [self _withVersionedDoc: rev.docID do: ^(VersionedDocument& doc) {
        BOOL ok = [CBLForestBridge loadBodyOfRevisionObject: rev options: options doc: doc];
        if (!ok)
            return kCBLStatusNotFound;
        if (options & kCBLIncludeAttachments)
            [self expandAttachmentsIn: rev options: options];
        return kCBLStatusOK;
    }];
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
    __block SequenceNumber sequence = rev.sequenceIfKnown;
    if (sequence > 0)
        return sequence;
    [self _withVersionedDoc: rev.docID do: ^(VersionedDocument& doc) {
        const Revision* revNode = doc.get(rev.revID);
        if (revNode)
            sequence = revNode->sequence;
        if (sequence > 0)
            rev.sequence = sequence;
        return kCBLStatusOK;
    }];
    return sequence;
}


- (NSString*) _indexedTextWithID: (UInt64)fullTextID {
    Assert(NO, @"FTS is out of service"); //FIX
}


#pragma mark - HISTORY:


- (CBL_Revision*) getParentRevision: (CBL_Revision*)rev {
    if (!rev.docID || !rev.revID)
        return nil;
    __block CBL_Revision* parent = nil;
    [self _withVersionedDoc: rev.docID do: ^(VersionedDocument& doc) {
        const Revision* revNode = doc.get(rev.revID);
        if (revNode) {
            const Revision* parentRevision = revNode->parent();
            if (parentRevision) {
                NSString* parentRevID = (NSString*)parentRevision->revID;
                parent = [[CBL_Revision alloc] initWithDocID: rev.docID
                                                       revID: parentRevID
                                                     deleted: parentRevision->isDeleted()];
            }
        }
        return kCBLStatusOK;
    }];
    return parent;
}


- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                      onlyCurrent: (BOOL)onlyCurrent
{
    __block CBL_RevisionList* revs = nil;
    [self _withVersionedDoc: docID do: ^(VersionedDocument& doc) {
        revs = [[CBL_RevisionList alloc] init];
        if (onlyCurrent) {
            auto revNodes = doc.currentRevisions();
            for (auto revNode = revNodes.begin(); revNode != revNodes.end(); ++revNode) {
                [revs addRev: [[CBL_Revision alloc] initWithDocID: docID
                                                            revID: (NSString*)(*revNode)->revID
                                                          deleted: (*revNode)->isDeleted()]];
            }
        } else {
            auto revNodes = doc.allRevisions();
            for (auto revNode = revNodes.begin(); revNode != revNodes.end(); ++revNode) {
                [revs addRev: [[CBL_Revision alloc] initWithDocID: docID
                                                            revID: (NSString*)revNode->revID
                                                          deleted: revNode->isDeleted()]];
            }
        }
        return kCBLStatusOK;
    }];
    return revs;
}


- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments
{
    unsigned generation = [CBL_Revision generationFromRevID: rev.revID];
    if (generation <= 1)
        return nil;
    __block NSMutableArray* revIDs = nil;
    [self _withVersionedDoc: rev.docID do: ^(VersionedDocument& doc) {
        revIDs = $marray();
        auto allRevisions = doc.allRevisions();
        for (auto rev = allRevisions.begin(); rev != allRevisions.end(); ++rev) {
            if (rev->revID.generation() < generation
                    && !rev->isDeleted() && rev->isBodyAvailable()
                    && !(onlyAttachments && !rev->hasAttachments())) {
                [revIDs addObject: (NSString*)rev->revID];
                if (limit && revIDs.count >= limit)
                    break;
            }
        }
        return kCBLStatusOK;
    }];
    return revIDs;
}


- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs {
    unsigned generation = [CBL_Revision generationFromRevID: rev.revID];
    if (generation <= 1 || revIDs.count == 0)
        return nil;
    revIDs = [revIDs sortedArrayUsingComparator: ^NSComparisonResult(NSString* id1, NSString* id2) {
        return CBLCompareRevIDs(id2, id1); // descending order of generation
    }];
    __block NSString* commonAncestor = nil;
    [self _withVersionedDoc: rev.docID do: ^(VersionedDocument& doc) {
        for (NSString* possibleRevID in revIDs) {
            revidBuffer revIDSlice(possibleRevID);
            if (revIDSlice.generation() <= generation && doc.get(revIDSlice) != NULL) {
                commonAncestor = possibleRevID;
                break;
            }
        }
        return kCBLStatusOK;
    }];
    return commonAncestor;
}
    

- (NSArray*) getRevisionHistory: (CBL_Revision*)rev {
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    Assert(revID && docID);
    __block NSArray* history = nil;
    [self _withVersionedDoc: docID do: ^(VersionedDocument& doc) {
        history = [CBLForestBridge getRevisionHistory: doc.get(revID)];
        return kCBLStatusOK;
    }];
    return history;
}


- (NSDictionary*) getRevisionHistoryDict: (CBL_Revision*)rev
                       startingFromAnyOf: (NSArray*)ancestorRevIDs
{
    __block NSDictionary* history = nil;
    [self _withVersionedDoc: rev.docID do: ^(VersionedDocument& doc) {
        history = [CBLForestBridge getRevisionHistoryOfNode: doc.get(rev.revID)
                                          startingFromAnyOf: ancestorRevIDs];
        return kCBLStatusOK;
    }];
    return history;
}


const CBLChangesOptions kDefaultCBLChangesOptions = {UINT_MAX, 0, NO, NO, YES};


- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                   options: (const CBLChangesOptions*)options
                                    filter: (CBLFilterBlock)filter
                                    params: (NSDictionary*)filterParams
                                    status: (CBLStatus*)outStatus
{
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    // Translate options to ForestDB:
    if (!options) options = &kDefaultCBLChangesOptions;
    auto forestOpts = DocEnumerator::Options::kDefault;
    forestOpts.limit = options->limit;
    forestOpts.inclusiveEnd = YES;
    forestOpts.includeDeleted = NO;
    BOOL includeDocs = options->includeDocs || options->includeConflicts || (filter != NULL);
    if (!includeDocs)
        forestOpts.contentOptions = Database::kMetaOnly;
    CBLContentOptions contentOptions = kCBLNoBody;
    if (includeDocs || filter)
        contentOptions = options->contentOptions;

    CBL_RevisionList* changes = [[CBL_RevisionList alloc] init];
    *outStatus = [self _try:^CBLStatus{
        for (DocEnumerator e(*_forest, lastSequence+1, UINT64_MAX, forestOpts); e.next(); ) {
            @autoreleasepool {
                VersionedDocument doc(*_forest, *e);
                NSArray* revIDs;
                if (options->includeConflicts)
                    revIDs = [CBLForestBridge getCurrentRevisionIDs: doc];
                else
                    revIDs = @[(NSString*)doc.revID()];
                for (NSString* revID in revIDs) {
                    CBL_MutableRevision* rev = [CBLForestBridge revisionObjectFromForestDoc: doc
                                                                                      revID: revID
                                                                         options: contentOptions];
                    Assert(rev);
                    if ([self runFilter: filter params: filterParams onRevision: rev])
                        [changes addRev: rev];
                }
            }
        }
        return kCBLStatusOK;
    }];
    return changes;
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
    CBL_Revision* rev = [self getDocumentWithID: [@"_design/" stringByAppendingString: path[0]]
                                    revisionID: nil];
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
    NSArray* filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _dir
                                                                             error: NULL];
    return [filenames my_map: ^id(NSString* filename) {
        NSString* viewName = [CBLView fileNameToViewName: filename];
        if (!viewName)
            return nil;
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

- (CBLView*) compileViewNamed: (NSString*)viewName status: (CBLStatus*)outStatus {
    CBLView* view = [self existingViewNamed: viewName];
    if (view && view.mapBlock)
        return view;
    
    // No CouchbaseLite view is defined, or it hasn't had a map block assigned;
    // see if there's a CouchDB view definition we can compile:
    NSString* language;
    NSDictionary* viewProps = $castIf(NSDictionary, [self getDesignDocFunction: viewName
                                                                           key: @"views"
                                                                      language: &language]);
    if (!viewProps) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    } else if (![CBLView compiler]) {
        *outStatus = kCBLStatusNotImplemented;
        return nil;
    }
    view = [self viewNamed: viewName];
    if (![view compileFromProperties: viewProps language: language]) {
        *outStatus = kCBLStatusCallbackError;
        return nil;
    }
    return view;
}


- (CBLQueryIteratorBlock) getAllDocs: (CBLQueryOptions*)options
                              status: (CBLStatus*)outStatus
{
    if (!options)
        options = [CBLQueryOptions new];
    auto forestOpts = DocEnumerator::Options::kDefault;
    BOOL includeDocs = (options->includeDocs || options.filter);
    forestOpts.descending = options->descending;
    forestOpts.inclusiveEnd = options->inclusiveEnd;
    if (!includeDocs && !(options->allDocsMode >= kCBLShowConflicts))
        forestOpts.contentOptions = Database::kMetaOnly;
    __block unsigned limit = options->limit;
    __block unsigned skip = options->skip;

    __block DocEnumerator e;
    if (options.keys) {
        std::vector<std::string> docIDs;
        for (NSString* docID in options.keys)
            docIDs.push_back(docID.UTF8String);
        e = DocEnumerator(*_forest, docIDs, forestOpts);
    } else {
        e = DocEnumerator(*_forest,
                          nsstring_slice(options.startKey),
                          nsstring_slice(options.endKey),
                          forestOpts);
    }

    return ^CBLQueryRow*() {
        while (e.next()) {
            VersionedDocument::Flags flags = VersionedDocument::flagsOfDocument(*e);
            BOOL deleted = (flags & VersionedDocument::kDeleted) != 0;
            if (deleted && options->allDocsMode != kCBLIncludeDeleted && !options.keys)
                continue; // skip this doc
            if (options->allDocsMode == kCBLOnlyConflicts && !(flags & VersionedDocument::kConflicted))
                continue; // skip this doc
            if (skip > 0) {
                --skip;
                continue;
            }

            VersionedDocument doc(*_forest, *e);
            NSString* docID = (NSString*)doc.docID();
            if (!doc.exists()) {
                LogTo(QueryVerbose, @"AllDocs: No such row with key=\"%@\"",
                      docID);
                return [[CBLQueryRow alloc] initWithDocID: nil
                                                 sequence: 0
                                                      key: docID
                                                    value: nil
                                            docProperties: nil];
            }

            NSString* revID = (NSString*)doc.revID();
            SequenceNumber sequence = doc.sequence();

            NSDictionary* docContents = nil;
            if (includeDocs) {
                // Fill in the document contents:
                docContents = [CBLForestBridge bodyOfNode: doc.currentRevision()
                                                  options: options->content];
                if (!docContents)
                    Warn(@"AllDocs: Unable to read body of doc %@", docID);
            }

            NSArray* conflicts = nil;
            if (options->allDocsMode >= kCBLShowConflicts && doc.isConflicted()) {
                conflicts = [CBLForestBridge getCurrentRevisionIDs: doc];
                if (conflicts.count == 1)
                    conflicts = nil;
            }

            NSDictionary* value = $dict({@"rev", revID},
                                        {@"deleted", (deleted ?$true : nil)},
                                        {@"_conflicts", conflicts});  // (not found in CouchDB)
            LogTo(QueryVerbose, @"AllDocs: Found row with key=\"%@\", value=%@",
                  docID, value);
            auto row = [[CBLQueryRow alloc] initWithDocID: docID
                                                 sequence: sequence
                                                      key: docID
                                                    value: value
                                            docProperties: docContents];
            if (!CBLRowPassesFilter(self, row, options))
                continue;

            if (limit > 0 && --limit == 0)
                e.close();
            return row;
        }
        return nil;
    };
}

- (void) postNotification: (NSNotification*)notification
{
    if (_dispatchQueue) {
        // NSNotificationQueue is runloop-based, doesn't work on dispatch queues. (#364)
        [self doAsync:^{
            [[NSNotificationCenter defaultCenter] postNotification: notification];
        }];
    } else {
        NSNotificationQueue* queue = [NSNotificationQueue defaultQueue];
        [queue enqueueNotification: notification
                      postingStyle: NSPostASAP
                      coalesceMask: NSNotificationNoCoalescing
                          forModes: @[NSRunLoopCommonModes]];
    }

}


@end
