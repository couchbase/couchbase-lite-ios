//
//  TDPusher.m
//  TouchDB
//
//  Created by Jens Alfke on 12/5/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDPusher.h"
#import "TDDatabase.h"
#import "TDRevision.h"
#import "TDInternal.h"


static NSDictionary* makeCouchRevisionList( NSArray* history );


@implementation TDPusher


- (BOOL) isPush {
    return YES;
}


- (void) start {
    if (_running)
        return;
    [super start];
    
    // Process existing changes since the last push:
    TDRevisionList* changes = [_db changesSinceSequence: [_lastSequence longLongValue] 
                                                options: nil];
    if (changes.count > 0)
        [self processInbox: changes];
    
    // Now listen for future changes (in continuous mode):
    if (_continuous) {
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbChanged:)
                                                     name: TDDatabaseChangeNotification object: _db];
    }
}

- (void) stop {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [super stop];
}

- (void) dbChanged: (NSNotification*)n {
    NSDictionary* userInfo = n.userInfo;
    // Skip revisions that came from the database I'm syncing to:
    if ([[userInfo objectForKey: @"source"] isEqual: _remote])
        return;
    [self addToInbox: [userInfo objectForKey: @"rev"]];
}


- (void) processInbox: (TDRevisionList*)changes {
    // Generate a set of doc/rev IDs in the JSON format that _revs_diff wants:
    NSMutableDictionary* diffs = $mdict();
    for (TDRevision* rev in changes) {
        NSString* docID = rev.docID;
        NSMutableArray* revs = [diffs objectForKey: docID];
        if (!revs) {
            revs = $marray();
            [diffs setObject: revs forKey: docID];
        }
        [revs addObject: rev.revID];
    }
    
    NSDictionary* results = [self sendRequest: @"POST" path: @"/_revs_diff" body: diffs];
    
    if (results.count) {
        // Go through the list of local changes again, selecting the ones the destination server
        // said were missing and mapping them to a JSON dictionary in the form _bulk_docs wants:
        NSArray* docsToSend = [changes.allRevisions my_map: ^(id rev) {
            NSArray* revs = [[results objectForKey: [rev docID]] objectForKey: @"missing"];
            if (![revs containsObject: [rev revID]])
                return (id)nil;
            // Get the revision's properties:
            NSMutableDictionary* properties;
            if ([rev deleted])
                properties = $mdict({@"_id", [rev docID]}, {@"_rev", [rev revID]}, {@"_deleted", $true});
            else {
                if (![_db loadRevisionBody: rev]) {
                    Warn(@"%@: Couldn't get local contents of %@", self, rev);
                    return nil;
                }
                properties = [[[rev properties] mutableCopy] autorelease];
            }
            
            // Add the _revisions list:
            [properties setValue: makeCouchRevisionList([_db getRevisionHistory: rev])
                          forKey: @"_revisions"];
            return properties;
        }];
        
        // Post the revisions to the destination. "new_edits":false means that the server should
        // use the given _rev IDs instead of making up new ones.
        LogTo(Sync, @"%@: Sending %u revisions", self, docsToSend.count);
        [self sendRequest: @"POST"
                     path: @"/_bulk_docs"
                     body: $dict({@"docs", docsToSend},
                                 {@"new_edits", $false})];
    }
    
    self.lastSequence = $sprintf(@"%lld", [changes.allRevisions.lastObject sequence]);
}


static BOOL parseRevID( NSString* revID, int* outNum, NSString** outSuffix) {
    NSScanner* scanner = [[NSScanner alloc] initWithString: revID];
    scanner.charactersToBeSkipped = nil;
    BOOL parsed = [scanner scanInt: outNum] && [scanner scanString: @"-" intoString: nil];
    *outSuffix = [revID substringFromIndex: scanner.scanLocation];
    [scanner release];
    return parsed && *outNum > 0 && (*outSuffix).length > 0;
}


static NSDictionary* makeCouchRevisionList( NSArray* history ) {
    if (!history)
        return nil;
    
    // Try to extract descending numeric prefixes:
    NSMutableArray* suffixes = $marray();
    id start = nil;
    int lastRevNo = -1;
    for (TDRevision* rev in history) {
        int revNo;
        NSString* suffix;
        if (parseRevID(rev.revID, &revNo, &suffix)) {
            if (!start)
                start = $object(revNo);
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




#if DEBUG

static TDRevision* mkrev(NSString* revID) {
    return [[[TDRevision alloc] initWithDocID: @"docid" revID: revID deleted: NO] autorelease];
}

TestCase(TDPusher_ParseRevID) {
    RequireTestCase(TDDatabase);
    int num;
    NSString* suffix;
    CAssert(parseRevID(@"1-utiopturoewpt", &num, &suffix));
    CAssertEq(num, 1);
    CAssertEqual(suffix, @"utiopturoewpt");
    
    CAssert(parseRevID(@"321-fdjfdsj-e", &num, &suffix));
    CAssertEq(num, 321);
    CAssertEqual(suffix, @"fdjfdsj-e");
    
    CAssert(!parseRevID(@"0-fdjfdsj-e", &num, &suffix));
    CAssert(!parseRevID(@"-4-fdjfdsj-e", &num, &suffix));
    CAssert(!parseRevID(@"5_fdjfdsj-e", &num, &suffix));
    CAssert(!parseRevID(@" 5-fdjfdsj-e", &num, &suffix));
    CAssert(!parseRevID(@"7 -foo", &num, &suffix));
    CAssert(!parseRevID(@"7-", &num, &suffix));
    CAssert(!parseRevID(@"7", &num, &suffix));
    CAssert(!parseRevID(@"eiuwtiu", &num, &suffix));
    CAssert(!parseRevID(@"", &num, &suffix));
}

TestCase(TDPusher_RevisionList) {
    NSArray* revs = $array(mkrev(@"4-jkl"), mkrev(@"3-ghi"), mkrev(@"2-def"));
    CAssertEqual(makeCouchRevisionList(revs), $dict({@"ids", $array(@"jkl", @"ghi", @"def")},
                                                    {@"start", $object(4)}));
    
    revs = $array(mkrev(@"4-jkl"), mkrev(@"2-def"));
    CAssertEqual(makeCouchRevisionList(revs), $dict({@"ids", $array(@"4-jkl", @"2-def")}));
    
    revs = $array(mkrev(@"12345"), mkrev(@"6789"));
    CAssertEqual(makeCouchRevisionList(revs), $dict({@"ids", $array(@"12345", @"6789")}));
}

#endif
