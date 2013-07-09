//
//  CBLLocalChangeTracker.m
//  CouchbaseLite
//
//  Created by Paul Mietz Egli on 4/23/13.
//
//

#import "CBLLocalChangeTracker.h"
#import "CBL_Server.h"
#import "CBLDatabase+Internal.h"
#import "CBL_DatabaseChange.h"
#import "CBLMisc.h"
#import "objc/message.h"

@interface CBLLocalChangeTracker ()
@property (nonatomic, strong) CBL_Server * server;
- (void)processOneShot;
- (void)processLongPoll;
- (NSDictionary*) changeDictForRev: (CBL_Revision*)rev;
- (NSArray*) revisionListToChanges:(CBL_RevisionList *)revs;
- (NSArray*) revisionListToChangesWithConflicts: (CBL_RevisionList *)revs;
@end

@implementation CBLLocalChangeTracker

@synthesize server;

/*
 - (void) changeTrackerReceivedChange: (NSDictionary*)change;
 - (void) changeTrackerReceivedChanges: (NSArray*)changes;
 - (void) changeTrackerStopped: (CBLChangeTracker*)tracker;

//        [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseChangesNotification
object: self
userInfo: $dict({@"changes", changes})];
 */


- (BOOL)start {
    LogTo(ChangeTracker, @"%@: Starting...", self);
    [super start];
    
    // find the server registered for the database URL
    Class cblURLProtocol = NSClassFromString(@"CBL_URLProtocol");
    Assert(cblURLProtocol, @"CBL_URLProtocol class not found; link CouchbaseLiteListener.framework");
    self.server = (CBL_Server *) objc_msgSend(cblURLProtocol, NSSelectorFromString(@"serverForURL:"), self.databaseURL);
    if (!self.server) {
        LogTo(ChangeTracker, @"Could not find server for URL %@", self.databaseURL);
        return NO;
    }

    if (self.mode == kOneShot) {
        [self processOneShot];
        return YES;
    }
    else if (self.mode == kLongPoll) {
        [self processLongPoll];
    }
    // kContinuous not supported atm...
    
    return NO;
}

- (void)stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(start)
                                               object: nil];    // cancel pending retries

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super stop];
}


#pragma mark -

- (void)processOneShot {
    __block CBLChangesOptions options = kDefaultCBLChangesOptions;
    options.includeConflicts = _includeConflicts;
    options.limit = _limit;
    options.includeDocs = NO;
    options.sortBySequence = !options.includeConflicts;
    
    [self.server tellDatabaseNamed:self.databaseName to:^(CBLDatabase * db) {
        // compile the changes filter, if provided
        CBLFilterBlock changesFilter = nil;
        if (self.filterName) {
            CBLStatus status;
            changesFilter = [db compileFilterNamed: self.filterName status: &status];
            if (!changesFilter)
                LogTo(ChangeTracker, @"Error compiling replication filter named %@ for one shot", self.filterName);
                return;
        }
        
        CBL_RevisionList * changes = [db changesSinceSequence: [self.lastSequenceID longLongValue]
                                                           options: &options
                                                            filter: changesFilter
                                                            params: self.filterParameters];
        if (!changes) {
            self.error = [NSError errorWithDomain: @"CBLLocalChangeTracker"
                                        code: db.lastDbError 
                                    userInfo: nil];

            return;
        }
        
        NSArray * changeList = nil;
        
        if (_includeConflicts)
            changeList = [self revisionListToChangesWithConflicts:changes];
        else
            changeList = [self revisionListToChanges:changes];
        
        [self.client changeTrackerReceivedChanges:changeList];
    }];
}

#pragma mark -

- (void)processLongPoll {
    [self.server tellDatabaseNamed:self.databaseName to:^(CBLDatabase * db) {
        CBLFilterBlock changesFilter = nil;
        if (self.filterName) {
            CBLStatus status;
            changesFilter = [db compileFilterNamed: self.filterName status: &status];
            if (!changesFilter)
                LogTo(ChangeTracker, @"Error compiling replication filter named %@ for long poll", self.filterName);
            return;
        }

        
        [[NSNotificationCenter defaultCenter] addObserverForName:CBL_DatabaseChangesNotification object:db queue:nil usingBlock:^(NSNotification *note) {
            NSArray* changes = (note.userInfo)[@"changes"];
            NSMutableArray * changeList = [NSMutableArray arrayWithCapacity:changes.count];
            for (CBL_DatabaseChange* change in changes) {
                CBL_Revision* rev = change.addedRevision;
                if (changesFilter && ![db runFilter: changesFilter params: self.filterParameters onRevision: rev])
                    continue;
                [changeList addObject:[self changeDictForRev:rev]];
            }
            [self.client changeTrackerReceivedChanges:changeList];
        }];
    }];
}


#pragma mark -

- (NSDictionary*) changeDictForRev: (CBL_Revision*)rev {
    return $dict({@"seq", @(rev.sequence)},
                 {@"id",  rev.docID},
                 {@"changes", $marray($dict({@"rev", rev.revID}))},
                 {@"deleted", rev.deleted ? $true : nil});
}

- (NSArray*) revisionListToChanges:(CBL_RevisionList *)revs {
    NSMutableArray * result = [NSMutableArray arrayWithCapacity:revs.count];
    for (CBL_Revision * rev in revs) {
        [result addObject:[self changeDictForRev:rev]];
    }
    return result;
}


- (NSArray*) revisionListToChangesWithConflicts: (CBL_RevisionList *)revs {
    // Assumes the changes are grouped by docID so that conflicts will be adjacent.
    NSMutableArray* entries = [NSMutableArray arrayWithCapacity: revs.count];
    NSString* lastDocID = nil;
    NSDictionary* lastEntry = nil;
    for (CBL_Revision* rev in revs) {
        NSString* docID = rev.docID;
        if ($equal(docID, lastDocID)) {
            [lastEntry[@"changes"] addObject: $dict({@"rev", rev.revID})];
        } else {
            lastEntry = [self changeDictForRev: rev];
            [entries addObject: lastEntry];
            lastDocID = docID;
        }
    }
    // After collecting revisions, sort by sequence:
    [entries sortUsingComparator: ^NSComparisonResult(id e1, id e2) {
        return CBLSequenceCompare([e1[@"seq"] longLongValue],
                                  [e2[@"seq"] longLongValue]);
    }];
    if (entries.count > self.limit)
        [entries removeObjectsInRange: NSMakeRange(self.limit, entries.count - self.limit)];
    return entries;
}


@end
