//
//  CBLDatabase+Internal.m
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
#import "CBLDatabase+LocalDocs.h"
#import "CBLInternal.h"
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

#import <CBForest/CBForest.h>
#import "CBForestVersions+JSON.h"

#import "MYBlockUtils.h"
#import "ExceptionUtils.h"


// Size of ForestDB buffer cache allocated for a database
#define kDBBufferCacheSize (8*1024*1024)


NSString* const CBL_DatabaseChangesNotification = @"CBLDatabaseChanges";
NSString* const CBL_DatabaseWillCloseNotification = @"CBL_DatabaseWillClose";
NSString* const CBL_DatabaseWillBeDeletedNotification = @"CBL_DatabaseWillBeDeleted";


@implementation CBLDatabase (Internal)


- (CBForestDB*) forestDB {
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
    if (![self deleteDatabaseFilesAtPath: dir error: NULL])
        return nil;
    CBLDatabase *db = [[self alloc] initWithDir: dir name: nil manager: nil readOnly: NO];
    if (![db open: nil])
        return nil;
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

        if (0) {
            // Appease the static analyzer by using these category ivars in this source file:
            _pendingAttachmentsByDigest = nil;
        }
    }
    return self;
}

- (NSString*) description {
    return $sprintf(@"%@[<%p>%@]", [self class], self, self.name);
}

- (BOOL) exists {
    return [[NSFileManager defaultManager] fileExistsAtPath: _dir];
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
    CBForestFileOptions options = _readOnly ? kCBForestDBReadOnly : kCBForestDBCreate;

    CBForestDBConfig config = {
        .bufferCacheSize = kDBBufferCacheSize,
        .walThreshold = 4096,
        .enableSequenceTree = YES,
        .compressDocBodies = YES,
    };

    _forest = [[CBForestDB alloc] initWithFile: forestPath
                                       options: options
                                        config: &config
                                         error: outError];
    if (!_forest)
        return NO;
    _forest.documentClass = [CBForestVersions class];

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
        [_forest close];
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

- (BOOL) closeInternal {
    if (!_isOpen)
        return NO;
    
    LogTo(CBLDatabase, @"Closing <%p> %@", self, _dir);
    Assert(_transactionLevel == 0, @"Can't close database while %u transactions active",
            _transactionLevel);
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

    [_forest close];

    [self closeLocalDocs];

    _isOpen = NO;
    _transactionLevel = 0;
    return YES;
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


#pragma mark - TRANSACTIONS & NOTIFICATIONS:


- (CBLStatus) _inTransaction: (CBLStatus(^)())block {
    LogTo(CBLDatabase, @"BEGIN transaction...");
    ++_transactionLevel;
    __block CBLStatus status = kCBLStatusException;
    [_forest inTransaction: ^BOOL{
        status = block();
        return !CBLStatusIsError(status);
    }];
    LogTo(CBLDatabase, @"END transaction (status=%d)", status);
    if (--_transactionLevel == 0)
        [self postChangeNotifications];
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
                [self closeForDeletion];
            }];
        }
    }
}


#pragma mark - GETTING DOCUMENTS:


- (CBForestVersions*) _forestDocWithID: (NSString*)docID
                                status: (CBLStatus*)outStatus
{
    NSError* error;
    CBForestVersions* doc = (CBForestVersions*)[_forest documentWithID: docID
                                                               options: 0 error: &error];
    if (outStatus != NULL) {
        if (doc)
            *outStatus = kCBLStatusOK;
        else if (!error || error.code == kCBForestErrorNotFound)
            *outStatus = kCBLStatusNotFound;
        else
            *outStatus = kCBLStatusDBError;
    }
    return doc;
}


- (CBL_MutableRevision*) revisionObjectFromForestDoc: (CBForestVersions*)doc
                                               revID: (NSString*)revID
                                             options: (CBLContentOptions)options
{
    BOOL deleted = [doc isRevisionDeleted: revID];
    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: doc.docID
                                                                    revID: revID
                                                                  deleted: deleted];
    rev.sequence = doc.sequence;
    if (![doc loadBodyOfRevisionObject: rev options: options])
        return nil;
    return rev;
}


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)revID
                            options: (CBLContentOptions)options
                             status: (CBLStatus*)outStatus
{
    CBForestVersions* doc = [self _forestDocWithID: docID status: outStatus];
    if (!doc)
        return nil;
    CBForestRevisionFlags revFlags = [doc flagsOfRevision: revID];
    BOOL deleted = (revFlags & kCBForestRevisionDeleted) != 0;
    if (revID == nil) {
        if (deleted) {
            *outStatus = kCBLStatusDeleted;
            return nil;
        }
        revID = doc.currentRevisionID;
    }
    if (!(revFlags & kCBForestRevisionHasBody)) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }

    CBL_MutableRevision* result = [self revisionObjectFromForestDoc: doc
                                                              revID: revID options: options];
    if (!result) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    if (options & kCBLIncludeAttachments)
        [self expandAttachmentsIn: result options: options];
    *outStatus = kCBLStatusOK;
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
    if (rev.body && rev.sequenceIfKnown && options==0)
        return kCBLStatusOK;  // no-op
    Assert(rev.docID && rev.revID);

    CBLStatus status;
    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: &status];
    if (!doc)
        return status;
    if ([doc flagsOfRevision: rev.revID] == 0)
        return kCBLStatusNotFound;
    if (![doc loadBodyOfRevisionObject: rev options: options])
        return kCBLStatusNotFound;
    if (options & kCBLIncludeAttachments)
        [self expandAttachmentsIn: rev options: options];
    return kCBLStatusOK;
}


- (CBL_Revision*) revisionByLoadingBody: (CBL_Revision*)rev
                                options: (CBLContentOptions)options
                                 status: (CBLStatus*)outStatus
{
    if (rev.body && rev.sequenceIfKnown && options==0)
        return rev;  // no-op
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
    if (sequence > 0)
        return sequence;
    CBLStatus status;
    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: &status];
    if (CBLStatusIsError(status))
        return 0;
    sequence = [doc sequenceOfRevision: rev.revID];
    if (sequence > 0)
        rev.sequence = sequence;
    return sequence;
}


- (NSString*) _indexedTextWithID: (UInt64)fullTextID {
    Assert(NO, @"FTS is out of service"); //FIX
}


#pragma mark - HISTORY:


- (CBL_Revision*) getParentRevision: (CBL_Revision*)rev {
    if (!rev.docID || !rev.revID)
        return nil;
    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: NULL];
    if (!doc)
        return nil;
    NSString* parentID = [doc parentIDOfRevision: rev.revID];
    if (!parentID)
        return nil;
    BOOL parentDeleted = ([doc flagsOfRevision: parentID] & kCBForestRevisionDeleted) != 0;
    return [[CBL_Revision alloc] initWithDocID: rev.docID
                                         revID: parentID
                                       deleted: parentDeleted];
}


- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                      onlyCurrent: (BOOL)onlyCurrent
{
    CBForestVersions* doc = [self _forestDocWithID: docID status: NULL];
    if (!doc)
        return nil;
    NSArray* revIDs = onlyCurrent ? doc.currentRevisionIDs : doc.allRevisionIDs;
    CBL_RevisionList* revs = [[CBL_RevisionList alloc] init];
        for (NSString* revID in revIDs) {
        [revs addRev: [[CBL_Revision alloc] initWithDocID: docID
                                                    revID: revID
                                                  deleted: [doc isRevisionDeleted: revID]]];
    }
    return revs;
}


- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments // unimplemented
{
    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: NULL];
    return [doc getPossibleAncestorRevisionIDs: rev.revID
                                         limit: limit
                               onlyAttachments: onlyAttachments];
}


- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs {
    if (revIDs.count == 0)
        return nil;
    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: NULL];
    return [doc findCommonAncestorOf: rev.revID withRevIDs: revIDs];
}
    

- (NSArray*) getRevisionHistory: (CBL_Revision*)rev {
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    Assert(revID && docID);
    CBForestVersions* doc = [self _forestDocWithID: docID status: NULL];
    return doc ? [doc getRevisionHistory: revID] : @[];
}


- (NSDictionary*) getRevisionHistoryDict: (CBL_Revision*)rev
                       startingFromAnyOf: (NSArray*)ancestorRevIDs
{
    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: NULL];
    return [doc getRevisionHistoryDict: rev.revID startingFromAnyOf: ancestorRevIDs];
}


const CBLChangesOptions kDefaultCBLChangesOptions = {UINT_MAX, 0, NO, NO, YES};


- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                   options: (const CBLChangesOptions*)options
                                    filter: (CBLFilterBlock)filter
                                    params: (NSDictionary*)filterParams
                                    status: (CBLStatus*)outStatus
{
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    if (!options) options = &kDefaultCBLChangesOptions;
    CBForestEnumerationOptions forestOpts = {
        .limit = options->limit,
        .inclusiveEnd = YES,
        .includeDeleted = YES,
    };
    BOOL includeDocs = options->includeDocs || options->includeConflicts || (filter != NULL);
    if (!includeDocs)
        forestOpts.contentOptions |= kCBForestDBMetaOnly;
    CBLContentOptions contentOptions = kCBLNoBody;
    if (includeDocs || filter)
        contentOptions = options->contentOptions;

    CBL_RevisionList* changes = [[CBL_RevisionList alloc] init];
    NSEnumerator* e = [_forest enumerateDocsFromSequence: lastSequence+1
                                              toSequence: kCBForestMaxSequence
                                                 options: &forestOpts error: NULL];
    for (CBForestVersions* doc in e) {
        @autoreleasepool {
            NSArray* revisions;
            if (options->includeConflicts) {
                revisions = doc.currentRevisionIDs;
                revisions = [revisions sortedArrayUsingComparator:^NSComparisonResult(id r1, id r2) {
                    return CBLCompareRevIDs(r1, r2);
                }];
            } else {
                revisions = @[doc.revID];
            }
            for (NSString* revID in revisions) {
                CBL_MutableRevision* rev = [self revisionObjectFromForestDoc: doc revID: revID
                                                                     options: contentOptions];
                if ([self runFilter: filter params: filterParams onRevision: rev])
                    [changes addRev: rev];
            }
        }
    }
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
    CBForestEnumerationOptions forestOpts = {
        .skip = options->skip,
        .limit = options->limit,
        .descending = options->descending,
        .inclusiveEnd = options->inclusiveEnd,
        .includeDeleted = (options->allDocsMode == kCBLIncludeDeleted) || options.keys != nil,
        .onlyConflicts = (options->allDocsMode == kCBLOnlyConflicts),
    };

    NSError* error;
    NSEnumerator* e;
    if (options.keys) {
        e = [_forest enumerateDocsWithKeys: options.keys
                                   options: &forestOpts error: &error];
    } else {
        e = [_forest enumerateDocsFromID: options.startKey toID: options.endKey
                                 options: &forestOpts error: &error];
    }
    if (!e) {
        *outStatus = CBLStatusFromNSError(error, kCBLStatusDBError);
        return nil;
    }

    return ^CBLQueryRow*() {
        CBForestVersions* doc = e.nextObject;
        if (!doc)
            return nil;
        NSString *docID = doc.docID, *revID = doc.revID;
        if (!doc.exists) {
            return [[CBLQueryRow alloc] initWithDocID: nil
                                             sequence: 0
                                                  key: docID
                                                value: nil
                                        docProperties: nil];
        }
        
        BOOL deleted = (doc.flags & kCBForestDocDeleted) != 0;
        SequenceNumber sequence = doc.sequence;

        NSDictionary* docContents = nil;
        if (options->includeDocs) {
            // Fill in the document contents:
            docContents = [doc bodyOfRevision: revID options: options->content];
            Assert(docContents);
        }

        NSArray* conflicts = nil;
        if (options->allDocsMode >= kCBLShowConflicts) {
            conflicts = doc.currentRevisionIDs;
            if (conflicts.count == 1)
                conflicts = nil;
        }

        NSDictionary* value = $dict({@"rev", revID},
                                    {@"deleted", (deleted ?$true : nil)},
                                    {@"_conflicts", conflicts});  // (not found in CouchDB)
        LogTo(ViewVerbose, @"AllDocs: Found row with key=\"%@\", value=%@",
              docID, value);
        return [[CBLQueryRow alloc] initWithDocID: docID
                                         sequence: sequence
                                              key: docID
                                            value: value
                                    docProperties: docContents];
    };
}


@end
