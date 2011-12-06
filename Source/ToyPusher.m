//
//  ToyPusher.m
//  ToyCouch
//
//  Created by Jens Alfke on 12/5/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyPusher.h"
#import "ToyDB.h"
#import "ToyRev.h"
#import "ToyDocument.h"

#import "CollectionUtils.h"
#import "Logging.h"


@implementation ToyPusher


- (void) start {
    if (_started)
        return;
    [super start];
    
    // Process existing changes since the last push:
    NSArray* changes = [_db changesSinceSequence: [_lastSequence intValue] options: nil];
    if (changes.count > 0)
        [self processInbox: changes];
    
    // Now listen for future changes (in continuous mode):
    if (_continuous) {
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbChanged:)
                                                     name: ToyDBChangeNotification object: _db];
    }
}

- (void) stop {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [super stop];
}

- (void) dbChanged: (NSNotification*)n {
    [self addToInbox: [n.userInfo objectForKey: @"rev"]];
}


- (void) processInbox: (NSArray*)changes {
    // Generate a set of doc/rev IDs in the JSON format that _revs_diff wants:
    NSMutableDictionary* diffs = $mdict();
    for (ToyRev* rev in changes) {
        NSString* docID = rev.docID;
        NSMutableArray* revs = [diffs objectForKey: docID];
        if (!revs) {
            revs = $marray();
            [diffs setObject: revs forKey: docID];
        }
        [revs addObject: rev.revID];
    }
    
    NSDictionary* results = [self postRequest: @"/_revs_diff" body: diffs];
    
    if (results.count) {
        // Go through the list of local changes again, selecting the ones the destination server
        // said were missing and mapping them to a JSON dictionary in the form _bulk_docs wants:
        NSArray* docsToSend = [changes my_map: ^(id rev) {
            NSArray* revs = [[results objectForKey: [rev docID]] objectForKey: @"missing"];
            if (![revs containsObject: [rev revID]])
                return (id)nil;
            else if ([rev deleted])
                return $dict({@"_id", [rev docID]}, {@"_rev", [rev revID]}, {@"_deleted", $true});
            else {
                ToyDocument* doc = [rev document];
                if (!doc) {
                    LogTo(Sync, @"%@: Fetching JSON of %@", self, rev);
                    doc = [_db getDocumentWithID: [rev docID] revisionID: [rev revID]];
                    if (!doc)
                        Warn(@"%@: Couldn't get contents of %@", self, rev);
                }
                return doc.properties;
            }
        }];
        
        // Post the revisions to the destination. "new_edits":false means that the server should
        // use the given _rev IDs instead of making up new ones.
        [self postRequest: @"/_bulk_docs"
                     body: $dict({@"docs", docsToSend},
                                 {@"new_edits", $false})];
    }
    
    self.lastSequence = $object([changes.lastObject sequence]);
}


@end
