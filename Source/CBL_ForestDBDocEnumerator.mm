//
//  CBL_ForestDBDocEnumerator.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/12/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBL_ForestDBDocEnumerator.h"
#import "c4DocEnumerator.h"
#import "CBLForestBridge.h"
extern "C" {
#import "CBL_ForestDBStorage.h"
}


@implementation CBL_ForestDBDocEnumerator
{
    CBL_ForestDBStorage* _storage;
    C4DocEnumerator *_enum;
    CBLAllDocsMode _allDocsMode;
    unsigned _limit, _skip;
    CBLQueryRowFilter _filter;
    BOOL _byKey, _includeDocs;
}


- (instancetype) initWithStorage: (CBL_ForestDBStorage*)storage
                         options: (CBLQueryOptions*)options
                           error: (C4Error*)outError
{
    self = [super initWithSequenceNumber: storage.lastSequence rows: nil];
    if (self) {
        _storage = storage;
        C4EnumeratorOptions c4options = {0, 0};
        _includeDocs = (options->includeDocs || options.filter);
        if (_includeDocs || options->allDocsMode == kCBLOnlyConflicts)
            c4options.flags |= kC4IncludeBodies;
        if (options->descending)
            c4options.flags |= kC4Descending;
        if (options->inclusiveStart)
            c4options.flags |= kC4InclusiveStart;
        if (options->inclusiveEnd)
            c4options.flags |= kC4InclusiveEnd;
        if (options->allDocsMode == kCBLIncludeDeleted)
            c4options.flags |= kC4IncludeDeleted;
        if (options->allDocsMode != kCBLOnlyConflicts)
            c4options.flags |= kC4IncludeNonConflicted;
        _limit = options->limit;
        _skip = options->skip;
        _filter = options.filter;
        _allDocsMode = options->allDocsMode;

        C4Database *db = (C4Database*)storage.forestDatabase;
        if (options.keys) {
            _byKey = YES;
            size_t nKeys = options.keys.count;
            C4Slice *keySlices = (C4Slice*)malloc(nKeys * sizeof(C4Slice));
            size_t i = 0;
            for (NSString* key in options.keys)
                keySlices[i++] = string2slice(key);
            c4options.flags |= kC4IncludeDeleted;
            _enum = c4db_enumerateSomeDocs(db, keySlices, nKeys, &c4options, outError);
            free(keySlices);
        } else {
            id startKey, endKey;
            if (options->descending) {
                startKey = CBLKeyForPrefixMatch(options.startKey, options->prefixMatchLevel);
                endKey = options.endKey;
            } else {
                startKey = options.startKey;
                endKey = CBLKeyForPrefixMatch(options.endKey, options->prefixMatchLevel);
            }
            _enum = c4db_enumerateAllDocs(db,
                                      string2slice(startKey),
                                      string2slice(endKey),
                                      &c4options,
                                      outError);
        }
        if (!_enum)
            return nil;
    }
    return self;
}


- (void)dealloc {
    c4enum_free(_enum);
}


- (CBLQueryRow*) generateNextRow {
    if (!_enum)
        return nil;
    C4Error c4err;
    while (c4enum_next(_enum, &c4err)) {
        C4DocumentInfo docInfo;
        c4enum_getDocumentInfo(_enum, &docInfo);
        NSString* docID = slice2string(docInfo.docID);
        if (!(docInfo.flags & kExists)) {
            LogVerbose(Query, @"AllDocs: No such row with key=\"%@\"", docID);
            return [[CBLQueryRow alloc] initWithDocID: nil
                                             sequence: 0
                                                  key: docID
                                                value: nil
                                          docRevision: nil];
        }

        bool deleted = (docInfo.flags & kDeleted) != 0;
        bool conflicted = (docInfo.flags & kConflicted) != 0;
        if (deleted && _allDocsMode != kCBLIncludeDeleted && !_byKey)
            continue; // skip deleted doc
        if (!conflicted && _allDocsMode == kCBLOnlyConflicts)
            continue; // skip non-conflicted doc
        if (_skip > 0) {
            --_skip;
            continue;
        }

        CBL_RevID* revID = slice2revID(docInfo.revID);

        // We'll need the full document if we're including doc bodies or listing conflicts:
        CLEANUP(C4Document)* doc = NULL;
        if (_includeDocs || (_allDocsMode >= kCBLShowConflicts && conflicted)) {
            doc = c4enum_getDocument(_enum, &c4err);
            if (!doc)
                break;
            if (!c4doc_loadRevisionBody(doc, &c4err))
                break;
        }

        CBL_Revision* docRevision = nil;
        if (_includeDocs) {
            // Fill in the document contents:
            CBLStatus status;
            docRevision = [CBLForestBridge revisionObjectFromForestDoc: doc
                                                                 docID: docID
                                                                 revID: revID
                                                              withBody: YES
                                                                status: &status];
            if (!docRevision)
                Warn(@"AllDocs: Unable to read body of doc %@: status %d", docID, status);
        }

        NSMutableArray<NSString*>* conflicts = nil;
        if (_allDocsMode >= kCBLShowConflicts && conflicted) {
            conflicts = [NSMutableArray new];
            [conflicts addObject: revID.asString];
            while (c4doc_selectNextLeafRevision(doc, false, false, NULL)) {
                [conflicts addObject: slice2string(doc->selectedRev.revID)];
            }
            if (conflicts.count == 1)
                conflicts = nil;
        }

        NSDictionary* value = $dict({@"rev", revID.asString},
                                    {@"deleted", (deleted ?$true : nil)},
                                    {@"_conflicts", conflicts});  // (not found in CouchDB)
        LogVerbose(Query, @"AllDocs: Found row with key=\"%@\", value=%@", docID, value);
        CBLQueryRow *row = [[CBLQueryRow alloc] initWithDocID: docID
                                                     sequence: docInfo.sequence
                                                          key: docID
                                                        value: value
                                                  docRevision: docRevision];
        if (_filter && ![self rowPassesFilter: row]) {
            LogVerbose(Query, @"   ... on 2nd thought, filter predicate skipped that row");
            continue;
        }

        if (_limit > 0 && --_limit == 0) {
            c4enum_free(_enum);
            _enum = NULL;
        }
        return row;
    }

    // End of enumeration:
    c4enum_free(_enum);
    _enum = NULL;
    if (c4err.code)
        Warn(@"AllDocs: Enumeration failed: %d", err2status(c4err));
    return nil;
}


- (BOOL) rowPassesFilter: (CBLQueryRow*)row {
    //FIX: I'm not supposed to know the delegates' real classes...
    [row moveToDatabase: (CBLDatabase*)_storage.delegate view: nil];
    if (!_filter(row))
        return NO;
    [row _clearDatabase];
    return YES;
}


@end
