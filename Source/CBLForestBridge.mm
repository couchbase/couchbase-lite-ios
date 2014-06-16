//
//  CBLForestBridge.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/14.
//
//

#import "CBLForestBridge.h"

using namespace forestdb;


@implementation CBLForestBridge


+ (NSData*) dataOfNode: (const RevNode*)node {
    try {
        return (NSData*)node->readBody();
    } catch (...) {
        return nil;
    }
}


+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (VersionedDocument&)doc
                                               revID: (NSString*)revID
                                             options: (CBLContentOptions)options
{
    CBL_MutableRevision* rev;
    NSString* docID = (NSString*)doc.docID();
    if (doc.nodesAvailable()) {
        const RevNode* node = doc.get(revidBuffer(revID));
        if (!node)
            return nil;
        rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                   revID: revID
                                                 deleted: node->isDeleted()];
        rev.sequence = node->sequence;
    } else {
        Assert(revID == nil || $equal(revID, (NSString*)doc.revID()));
        rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                   revID: (NSString*)doc.revID()
                                                 deleted: doc.isDeleted()];
        rev.sequence = doc.sequence();
    }
    if (![self loadBodyOfRevisionObject: rev options: options doc: doc])
        return nil;
    return rev;
}


+ (BOOL) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                          options: (CBLContentOptions)options
                              doc: (VersionedDocument&)doc
{
    // If caller wants no body and no metadata props, this is a no-op:
    if (options == kCBLNoBody)
        return YES;

    const RevNode* node = doc.get(revidBuffer(rev.revID));
    if (!node)
        return NO;
    NSData* json = nil;
    if (!(options & kCBLNoBody)) {
        json = [self dataOfNode: node];
        if (!json)
            return NO;
    }

    rev.sequence = node->sequence;

    NSMutableDictionary* extra = $mdict();
    [self addContentProperties: options into: extra node: node];
    if (json.length > 0)
        rev.asJSON = [CBLJSON appendDictionary: extra toJSONDictionaryData: json];
    else
        rev.properties = extra;
    return YES;
}


+ (NSDictionary*) bodyOfNode: (const RevNode*)node
                     options: (CBLContentOptions)options
{
    // If caller wants no body and no metadata props, this is a no-op:
    if (options == kCBLNoBody)
        return @{};

    NSData* json = nil;
    if (!(options & kCBLNoBody)) {
        json = [self dataOfNode: node];
        if (!json)
            return nil;
    }
    NSMutableDictionary* properties = [CBLJSON JSONObjectWithData: json
                                                          options: NSJSONReadingMutableContainers
                                                            error: NULL];
    [self addContentProperties: options into: properties node: node];
    return properties;
}


+ (void) addContentProperties: (CBLContentOptions)options
                         into: (NSMutableDictionary*)dst
                         node: (const RevNode*)node
{
    NSString* revID = (NSString*)node->revID;
    Assert(revID);
    const VersionedDocument* doc = (const VersionedDocument*)node->owner;
    dst[@"_id"] = (NSString*)doc->docID();
    dst[@"_rev"] = revID;

    if (node->isDeleted())
        dst[@"_deleted"] = $true;

    // Get more optional stuff to put in the properties:
    if (options & kCBLIncludeLocalSeq)
        dst[@"_local_seq"] = @(node->sequence);

    if (options & kCBLIncludeRevs)
        dst[@"_revisions"] = [self getRevisionHistoryOfNode: node startingFromAnyOf: nil];

    if (options & kCBLIncludeRevsInfo) {
        dst[@"_revs_info"] = [self mapHistoryOfNode: node
                                            through: ^id(const RevNode *node)
        {
            NSString* status = @"available";
            if (node->isDeleted())
                status = @"deleted";
            else if (!node->isBodyAvailable())
                status = @"missing";
            return $dict({@"rev", (NSString*)node->revID},
                         {@"status", status});
        }];
    }

    if (options & kCBLIncludeConflicts) {
        auto nodes = doc->currentNodes();
        if (nodes.size() > 1) {
            NSMutableArray* conflicts = $marray();
            for (auto node = nodes.begin(); node != nodes.end(); ++node) {
                if (!(*node)->isDeleted()) {
                    NSString* nodeRevID = (NSString*)(*node)->revID;
                    if (!$equal(nodeRevID, revID))
                        [conflicts addObject: nodeRevID];
                }
            }
            if (conflicts.count > 0)
                dst[@"_conflicts"] = conflicts;
        }
    }

    if (!options & kCBLIncludeAttachments)
        [dst removeObjectForKey: @"_attachments"];
}


+ (NSArray*) getCurrentRevisionIDs: (VersionedDocument&)doc {
    NSMutableArray* currentRevIDs = $marray();
    auto nodes = doc.currentNodes();
    for (auto node = nodes.begin(); node != nodes.end(); ++node)
        if (!(*node)->isDeleted())
            [currentRevIDs addObject: (NSString*)(*node)->revID];
    [currentRevIDs sortUsingComparator:^NSComparisonResult(id r1, id r2) {
        return CBLCompareRevIDs(r1, r2);
    }];
    return currentRevIDs;
}


+ (NSArray*) mapHistoryOfNode: (const RevNode*)node
                      through: (id(^)(const RevNode*))block
{
    NSMutableArray* history = $marray();
    for (; node; node = node->parent())
        [history addObject: block(node)];
    return history;
}


+ (NSArray*) getRevisionHistory: (const RevNode*)node
{
    const VersionedDocument* doc = (const VersionedDocument*)node->owner;
    NSString* docID = (NSString*)doc->docID();
    return [self mapHistoryOfNode: node
                          through: ^id(const RevNode *node)
    {
        CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                        revID:(NSString*)node->revID
                                                                      deleted: node->isDeleted()];
        rev.missing = !node->isBodyAvailable();
        return rev;
    }];
}


+ (NSDictionary*) getRevisionHistoryOfNode: (const RevNode*)node
                         startingFromAnyOf: (NSArray*)ancestorRevIDs
{
    NSArray* history = [self getRevisionHistory: node]; // (this is in reverse order, newest..oldest
    if (ancestorRevIDs.count > 0) {
        NSUInteger n = history.count;
        for (NSUInteger i = 0; i < n; ++i) {
            if ([ancestorRevIDs containsObject: [history[i] revID]]) {
                history = [history subarrayWithRange: NSMakeRange(0, i+1)];
                break;
            }
        }
    }
    return makeRevisionHistoryDict(history);
}


static NSDictionary* makeRevisionHistoryDict(NSArray* history) {
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


+ (NSArray*) getPossibleAncestorRevisionIDs: (NSString*)revID
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments // unimplemented
                                        doc: (VersionedDocument&)doc
{
    unsigned generation = [CBL_Revision generationFromRevID: revID];
    if (generation <= 1)
        return nil;

    NSMutableArray* revIDs = $marray();

    auto allNodes = doc.allNodes();
    for (auto node = allNodes.begin(); node != allNodes.end(); ++node) {
        if (node->revID.generation() < generation
                    && !node->isDeleted() && node->isBodyAvailable()) {
            [revIDs addObject: (NSString*)node->revID];
            if (limit && revIDs.count >= limit)
                break;
        }
    }
    return revIDs;
}


+ (NSString*) findCommonAncestorOf: (NSString*)revID
                        withRevIDs: (NSArray*)revIDs
                               doc: (VersionedDocument&)doc
{
    unsigned generation = [CBL_Revision generationFromRevID: revID];
    if (generation <= 1 || revIDs.count == 0)
        return nil;

    revIDs = [revIDs sortedArrayUsingComparator: ^NSComparisonResult(NSString* id1, NSString* id2) {
        return CBLCompareRevIDs(id2, id1); // descending order of generation
    }];
    for (NSString* possibleRevID in revIDs) {
        revidBuffer revIDSlice(possibleRevID);
        if (revIDSlice.generation() <= generation && doc.get(revIDSlice) != NULL) {
            return possibleRevID;
        }
    }
    return nil;
}
    

@end



CBLStatus CBLStatusFromForestDBStatus(int fdbStatus) {
    switch (fdbStatus) {
        case FDB_RESULT_SUCCESS:
            return kCBLStatusOK;
        case FDB_RESULT_KEY_NOT_FOUND:
        case FDB_RESULT_NO_SUCH_FILE:
            return kCBLStatusNotFound;
        case FDB_RESULT_RONLY_VIOLATION:
            return kCBLStatusForbidden;
        case FDB_RESULT_CHECKSUM_ERROR:
        case FDB_RESULT_FILE_CORRUPTION:
        case error::CorruptRevisionData:
            return kCBLStatusCorruptError;
        case error::BadRevisionID:
            return kCBLStatusBadID;
        default:
            return kCBLStatusDBError;
    }
}



#pragma mark - TESTS:
#if DEBUG

static CBL_Revision* mkrev(NSString* revID) {
    return [[CBL_Revision alloc] initWithDocID: @"docid" revID: revID deleted: NO];
}


TestCase(CBL_Database_MakeRevisionHistoryDict) {
    NSArray* revs = @[mkrev(@"4-jkl"), mkrev(@"3-ghi"), mkrev(@"2-def")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"jkl", @"ghi", @"def"]},
                                                      {@"start", @4}));

    revs = @[mkrev(@"4-jkl"), mkrev(@"2-def")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"4-jkl", @"2-def"]}));

    revs = @[mkrev(@"12345"), mkrev(@"6789")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"12345", @"6789"]}));
}

#endif
