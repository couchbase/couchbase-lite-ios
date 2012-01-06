//
//  TDPusher.m
//  TouchDB
//
//  Created by Jens Alfke on 12/5/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDPusher.h"
#import "TDDatabase.h"
#import "TDRevision.h"
#import "TDInternal.h"


@implementation TDPusher


@synthesize filter=_filter;


- (void)dealloc {
    [_filter release];
    [super dealloc];
}


- (BOOL) isPush {
    return YES;
}


- (void) start {
    if (_running)
        return;
    [super start];
    
    // Process existing changes since the last push:
    TDRevisionList* changes = [_db changesSinceSequence: [_lastSequence longLongValue] 
                                                options: nil filter: _filter];
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
    // Skip revisions that originally came from the database I'm syncing to:
    if ([[userInfo objectForKey: @"source"] isEqual: _remote])
        return;
    TDRevision* rev = [userInfo objectForKey: @"rev"];
    if (!_filter || _filter(rev))
        [self addToInbox: rev];
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
    
    // Call _revs_diff on the target db:
    [self sendAsyncRequest: @"POST" path: @"/_revs_diff" body: diffs
              onCompletion:^(NSDictionary* results, NSError* error) {
        if (results.count) {
            // Go through the list of local changes again, selecting the ones the destination server
            // said were missing and mapping them to a JSON dictionary in the form _bulk_docs wants:
            NSArray* docsToSend = [changes.allRevisions my_map: ^(id rev) {
                NSMutableDictionary* properties;
                @autoreleasepool {
                    NSArray* revs = [[results objectForKey: [rev docID]] objectForKey: @"missing"];
                    if (![revs containsObject: [rev revID]])
                        return (id)nil;
                    // Get the revision's properties:
                    if ([rev deleted])
                        properties = [$mdict({@"_id", [rev docID]}, {@"_rev", [rev revID]}, {@"_deleted", $true}) retain];
                    else {
                        // OPT: Shouldn't include all attachment bodies, just ones that have changed
                        // OPT: Should send docs with many or big attachments as multipart/related
                        if (![_db loadRevisionBody: rev options: kTDIncludeAttachments]) {
                            Warn(@"%@: Couldn't get local contents of %@", self, rev);
                            return nil;
                        }
                        properties = [[rev properties] mutableCopy];
                    }
                    
                    // Add the _revisions list:
                    [properties setValue: [_db getRevisionHistoryDict: rev] forKey: @"_revisions"];
                }
                return [properties autorelease];
            }];
            
            // Post the revisions to the destination. "new_edits":false means that the server should
            // use the given _rev IDs instead of making up new ones.
            NSUInteger numDocsToSend = docsToSend.count;
            LogTo(Sync, @"%@: Sending %u revisions", self, numDocsToSend);
            self.changesTotal += numDocsToSend;
            [self sendAsyncRequest: @"POST"
                         path: @"/_bulk_docs"
                         body: $dict({@"docs", docsToSend},
                                     {@"new_edits", $false})
                 onCompletion: ^(NSDictionary* response, NSError *error) {
                     if (!error)
                         self.lastSequence = $sprintf(@"%lld",
                                                      [changes.allRevisions.lastObject sequence]);
                     self.changesProcessed += numDocsToSend;
                 }
             ];
        }
    }];
}


@end
