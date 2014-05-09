//
//  CBForestVersions+JSON.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/14.
//
//

#import "CBForestVersions+JSON.h"


@implementation CBForestVersions (JSON)


- (BOOL) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                          options: (CBLContentOptions)options
{
    // If caller wants no body and no metadata props, this is a no-op:
    if (options == kCBLNoBody)
        return YES;

    NSString* revID = rev.revID;
    NSData* json = nil;
    if (!(options & kCBLNoBody)) {
        json = [self dataOfRevision: revID];
        if (!json)
            return NO;
    }

    rev.sequence = [self sequenceOfRevision: revID];

    NSMutableDictionary* extra = $mdict();
    [self addContentProperties: options forRevision: revID into: extra];
    if (json.length > 0)
        rev.asJSON = [CBLJSON appendDictionary: extra toJSONDictionaryData: json];
    else
        rev.properties = extra;
    return YES;
}


- (NSDictionary*) bodyOfRevision: (NSString*)revID
                         options: (CBLContentOptions)options
{
    // If caller wants no body and no metadata props, this is a no-op:
    if (options == kCBLNoBody)
        return @{};

    NSData* json = nil;
    if (!(options & kCBLNoBody)) {
        json = [self dataOfRevision: revID];
        if (!json)
            return nil;
    }
    NSMutableDictionary* properties = [CBLJSON JSONObjectWithData: json
                                                          options: NSJSONReadingMutableContainers
                                                            error: NULL];
    [self addContentProperties: options forRevision: revID into: properties];
    return properties;
}


- (void) addContentProperties: (CBLContentOptions)options
                  forRevision: (NSString*)revID
                         into: (NSMutableDictionary*)dst
{
    dst[@"_id"] = self.docID;
    dst[@"_rev"] = revID;

    CBForestRevisionFlags flags;
    CBForestSequence sequence;
    if (![self getRevision: revID flags: &flags sequence: &sequence])
        return;

    if (flags & kCBForestRevisionDeleted)
        dst[@"_deleted"] = $true;

    // Get more optional stuff to put in the properties:
    if (options & kCBLIncludeLocalSeq)
        dst[@"_local_seq"] = @(sequence);

    if (options & kCBLIncludeRevs)
        dst[@"_revisions"] = [self getRevisionHistoryDict: revID startingFromAnyOf: nil];

    if (options & kCBLIncludeRevsInfo) {
        dst[@"_revs_info"] = [[self getRevisionHistory: revID] my_map: ^id(CBL_Revision* rev) {
            NSString* status = @"available";
            if (rev.deleted)
                status = @"deleted";
            else if (rev.missing)
                status = @"missing";
            return $dict({@"rev", [rev revID]}, {@"status", status});
        }];
    }

    if (options & kCBLIncludeConflicts) {
        NSArray* current = self.currentRevisionIDs;
        if (current.count > 1) {
            dst[@"_conflicts"] = [current my_map: ^(NSString* aRev) {
                return ($equal(aRev, revID) || [self isRevisionDeleted: aRev]) ? nil : aRev;
            }];
        }
    }

    if (!options & kCBLIncludeAttachments)
        [dst removeObjectForKey: @"_attachments"];
}


- (NSArray*) getRevisionHistory: (NSString*)revID {
    NSMutableArray* history = $marray();
    for (NSString* ancestorID in [self historyOfRevision: revID]) {
        CBForestRevisionFlags flags = [self flagsOfRevision: ancestorID];
        BOOL deleted = (flags & kCBForestRevisionDeleted) != 0;
        CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: self.docID
                                                                        revID: ancestorID
                                                                      deleted: deleted];
        rev.missing = (flags & kCBForestRevisionHasBody) == 0
                   || [self dataOfRevision: ancestorID] == nil;
        [history addObject: rev];
    }
    return history;
}


- (NSDictionary*) getRevisionHistoryDict: (NSString*)revID
                       startingFromAnyOf: (NSArray*)ancestorRevIDs
{
    NSArray* history = [self getRevisionHistory: revID]; // (this is in reverse order, newest..oldest
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


- (NSArray*) getPossibleAncestorRevisionIDs: (NSString*)revID
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments // unimplemented
{
    unsigned generation = [CBL_Revision generationFromRevID: revID];
    if (generation <= 1)
        return nil;

    NSMutableArray* revIDs = $marray();
    for (NSString* possibleRevID in self.allRevisionIDs) {
        if ([CBL_Revision generationFromRevID: possibleRevID] < generation) {
            CBForestRevisionFlags flags = [self flagsOfRevision: possibleRevID];
            if (!(flags & kCBForestRevisionDeleted) && (flags & kCBForestRevisionHasBody)) {
                // Does it REALLY have a body that hasn't been compacted?
                if ([self dataOfRevision: possibleRevID] != nil) {
                    [revIDs addObject: possibleRevID];
                    if (limit && revIDs.count >= limit)
                        break;
                }
            }
        }
    }
    return revIDs;
}


- (NSString*) findCommonAncestorOf: (NSString*)revID withRevIDs: (NSArray*)revIDs {
    unsigned generation = [CBL_Revision generationFromRevID: revID];
    if (generation <= 1 || revIDs.count == 0)
        return nil;

    revIDs = [revIDs sortedArrayUsingComparator: ^NSComparisonResult(NSString* id1, NSString* id2) {
        return CBLCompareRevIDs(id2, id1); // descending order of generation
    }];
    for (NSString* possibleRevID in revIDs) {
        if ([self flagsOfRevision: possibleRevID] != 0) {
            if ([CBL_Revision generationFromRevID: possibleRevID] <= generation) {
                return possibleRevID;
            }
        }
    }
    return nil;
}
    

@end



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
