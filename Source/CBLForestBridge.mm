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


static NSData* dataOfNode(const Revision* rev) {
    if (rev->body.buf)
        return rev->body.uncopiedNSData();
    try {
        return rev->readBody().copiedNSData();
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
    if (doc.revsAvailable()) {
        const Revision* revNode = doc.get(revID);
        if (!revNode)
            return nil;
        rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                   revID: revID
                                                 deleted: revNode->isDeleted()];
        rev.sequence = revNode->sequence;
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


+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (VersionedDocument&)doc
                                            sequence: (forestdb::sequence)sequence
                                             options: (CBLContentOptions)options
{
    const Revision* revNode = doc.getBySequence(sequence);
    if (!revNode)
        return nil;
    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: (NSString*)doc.docID()
                                                                    revID: (NSString*)revNode->revID
                                                                  deleted: revNode->isDeleted()];
    if (![self loadBodyOfRevisionObject: rev options: options doc: doc])
        return nil;
    rev.sequence = sequence;
    return rev;
}


+ (BOOL) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                          options: (CBLContentOptions)options
                              doc: (VersionedDocument&)doc
{
    // If caller wants no body and no metadata props, this is a no-op:
    if (options == kCBLNoBody)
        return YES;

    const Revision* revNode = doc.get(rev.revID);
    if (!revNode)
        return NO;
    NSData* json = nil;
    if (!(options & kCBLNoBody)) {
        json = dataOfNode(revNode);
        if (!json)
            return NO;
    }

    rev.sequence = revNode->sequence;

    NSMutableDictionary* extra = $mdict();
    [self addContentProperties: options into: extra rev: revNode];
    if (json.length > 0)
        rev.asJSON = [CBLJSON appendDictionary: extra toJSONDictionaryData: json];
    else
        rev.properties = extra;
    return YES;
}


+ (NSDictionary*) bodyOfNode: (const Revision*)rev
                     options: (CBLContentOptions)options
{
    // If caller wants no body and no metadata props, this is a no-op:
    if (options == kCBLNoBody)
        return @{};

    NSData* json = nil;
    if (!(options & kCBLNoBody)) {
        json = dataOfNode(rev);
        if (!json)
            return nil;
    }
    NSMutableDictionary* properties = [CBLJSON JSONObjectWithData: json
                                                          options: NSJSONReadingMutableContainers
                                                            error: NULL];
    Assert(properties, @"Unable to parse doc from db: %@", json.my_UTF8ToString);
    [self addContentProperties: options into: properties rev: rev];
    return properties;
}


+ (void) addContentProperties: (CBLContentOptions)options
                         into: (NSMutableDictionary*)dst
                         rev: (const Revision*)rev
{
    NSString* revID = (NSString*)rev->revID;
    Assert(revID);
    const VersionedDocument* doc = (const VersionedDocument*)rev->owner;
    dst[@"_id"] = (NSString*)doc->docID();
    dst[@"_rev"] = revID;

    if (rev->isDeleted())
        dst[@"_deleted"] = $true;

    // Get more optional stuff to put in the properties:
    if (options & kCBLIncludeLocalSeq)
        dst[@"_local_seq"] = @(rev->sequence);

    if (options & kCBLIncludeRevs)
        dst[@"_revisions"] = [self getRevisionHistoryOfNode: rev startingFromAnyOf: nil];

    if (options & kCBLIncludeRevsInfo) {
        dst[@"_revs_info"] = [self mapHistoryOfNode: rev
                                            through: ^id(const Revision *rev)
        {
            NSString* status = @"available";
            if (rev->isDeleted())
                status = @"deleted";
            else if (!rev->isBodyAvailable())
                status = @"missing";
            return $dict({@"rev", (NSString*)rev->revID},
                         {@"status", status});
        }];
    }

    if (options & kCBLIncludeConflicts) {
        auto revs = doc->currentRevisions();
        if (revs.size() > 1) {
            NSMutableArray* conflicts = $marray();
            for (auto rev = revs.begin(); rev != revs.end(); ++rev) {
                if (!(*rev)->isDeleted()) {
                    NSString* revRevID = (NSString*)(*rev)->revID;
                    if (!$equal(revRevID, revID))
                        [conflicts addObject: revRevID];
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
    auto revs = doc.currentRevisions();
    for (auto rev = revs.begin(); rev != revs.end(); ++rev)
        if (!(*rev)->isDeleted())
            [currentRevIDs addObject: (NSString*)(*rev)->revID];
    return currentRevIDs;
}


+ (NSArray*) mapHistoryOfNode: (const Revision*)rev
                      through: (id(^)(const Revision*))block
{
    NSMutableArray* history = $marray();
    for (; rev; rev = rev->parent())
        [history addObject: block(rev)];
    return history;
}


+ (NSArray*) getRevisionHistory: (const Revision*)revNode
{
    const VersionedDocument* doc = (const VersionedDocument*)revNode->owner;
    NSString* docID = (NSString*)doc->docID();
    return [self mapHistoryOfNode: revNode
                          through: ^id(const Revision *ancestor)
    {
        CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                revID: (NSString*)ancestor->revID
                                                              deleted: ancestor->isDeleted()];
        rev.missing = !ancestor->isBodyAvailable();
        return rev;
    }];
}


+ (NSDictionary*) getRevisionHistoryOfNode: (const Revision*)rev
                         startingFromAnyOf: (NSArray*)ancestorRevIDs
{
    NSArray* history = [self getRevisionHistory: rev]; // (this is in reverse order, newest..oldest
    if (ancestorRevIDs.count > 0) {
        NSUInteger n = history.count;
        for (NSUInteger i = 0; i < n; ++i) {
            if ([ancestorRevIDs containsObject: [history[i] revID]]) {
                history = [history subarrayWithRange: NSMakeRange(0, i+1)];
                break;
            }
        }
    }
    return [self makeRevisionHistoryDict: history];
}


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
