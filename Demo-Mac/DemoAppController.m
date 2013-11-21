//
//  DemoAppController.m
//  CouchCocoa
//
//  Created by Jens Alfke on 6/1/11.
//  Copyright (c) 2011-2013 Couchbase, Inc, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "DemoAppController.h"
#import "DemoQuery.h"
#import "CBLJSON.h"
#import "Test.h"
#import "MYBlockUtils.h"
#import <CouchbaseLite/CouchbaseLite.h>

#undef FOR_TESTING_PURPOSES
#ifdef FOR_TESTING_PURPOSES
#import <CouchbaseLiteListener/CBLListener.h>
@interface DemoAppController () <CBLViewCompiler>
@end
static CBLListener* sListener;
#endif

#define ENABLE_REPLICATION


#define kChangeGlowDuration 3.0


int main (int argc, const char * argv[]) {
    RunTestCases(argc,argv);
    return NSApplicationMain(argc, argv);
}


@implementation DemoAppController


@synthesize query = _query;


- (void) applicationDidFinishLaunching: (NSNotification*)n {
    NSDictionary* bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString* dbName = bundleInfo[@"DemoDatabase"];
    if (!dbName) {
        NSLog(@"FATAL: Please specify a CouchbaseLite database name in the app's Info.plist under the 'DemoDatabase' key");
        exit(1);
    }
    
    NSError* error;
    _database = [[CBLManager sharedInstance] databaseNamed: dbName
                                                                     error: &error];
    if (!_database) {
        NSAssert(NO, @"Error creating db: %@", error);
    }
    
    // Create a 'view' containing list items sorted by date:
    [[_database viewNamed: @"byDate"] setMapBlock: MAPBLOCK({
        id date = doc[@"created_at"];
        if (date) emit(date, doc);
    }) version: @"1.0"];
    
    // and a validation function requiring parseable dates:
    [_database setValidationNamed: @"created_at" asBlock: VALIDATIONBLOCK({
        if (newRevision.isDeletion)
            return YES;
        id date = newRevision[@"created_at"];
        if (date && ! [CBLJSON dateWithJSONObject: date]) {
            context.errorMessage = [@"invalid date " stringByAppendingString: date];
            return NO;
        }
        return YES;
    })];
    
    // And why not a filter, just to allow some simple testing of filtered _changes.
    // For example, try curl 'http://localhost:8888/demo-shopping/_changes?filter=default/checked'
    [_database setFilterNamed: @"checked" asBlock: FILTERBLOCK({
        return [revision[@"check"] boolValue];
    })];

    
    CBLQuery* q = [[_database viewNamed: @"byDate"] createQuery];
    q.descending = YES;
    self.query = [[DemoQuery alloc] initWithQuery: q
                                       modelClass: _tableController.objectClass];
    
    // Start watching any persistent replications already configured:
    [self startContinuousSyncWith: self.syncURL];
    
#ifdef FOR_TESTING_PURPOSES
    // Start a listener socket:
    [server tellCBLServer: ^(CBL_Server* tdServer) {
        // Register support for handling certain JS functions used in the CouchbaseLite unit tests:
        [CBLView setCompiler: self];
        
        sListener = [[CBLListener alloc] initWithCBLServer: tdServer port: 8888];
        [sListener start];
    }];

#endif
}


- (IBAction) applicationWillTerminate:(id)sender {
    [_database.manager close];
}


- (IBAction) compact: (id)sender {
    [_database compact: NULL];
}


#pragma mark - SYNC UI:


- (NSURL*) currentURLFromField {
    NSString* urlStr = _syncURLField.stringValue;
    NSURL* url = nil;
    if (urlStr.length > 0) {
        url = [NSURL URLWithString: urlStr];
        if (![url.scheme hasPrefix: @"http"]) 
            url = nil;
    }
    return url;
}


- (void) setSyncConfiguringDefault: (BOOL)configuringDefault {
    _syncConfiguringDefault = configuringDefault;
    _syncPushCheckbox.controlView.hidden = configuringDefault;
}


- (IBAction) configureSync: (id)sender {
    [self setSyncConfiguringDefault: YES];
    _syncURLField.objectValue = self.syncURL.absoluteString;
    [NSApp beginSheet: _syncConfigSheet modalForWindow: _window
        modalDelegate: self
       didEndSelector:@selector(configureSyncFinished:returnCode:)
          contextInfo: NULL];
}

- (IBAction) oneShotSync: (id)sender {
    [self setSyncConfiguringDefault: NO];
    [NSApp beginSheet: _syncConfigSheet modalForWindow: _window
        modalDelegate: self
       didEndSelector:@selector(configureSyncFinished:returnCode:)
          contextInfo: NULL];
}

- (IBAction) dismissSyncConfigSheet:(id)sender {
    NSInteger returnCode = [sender tag];
    if (returnCode == NSOKButton) {
        if (_syncURLField.stringValue.length > 0 && !self.currentURLFromField) {
            NSBeep();
            return;
        }
    }
    [NSApp endSheet: _syncConfigSheet returnCode: returnCode];
}

- (void) configureSyncFinished:(NSWindow *)sheet returnCode:(NSInteger)returnCode {
    [sheet orderOut: self];
    NSURL* url = self.currentURLFromField;
    if (returnCode != NSOKButton || !url)
        return;
    
    if (_syncConfiguringDefault) {
        self.syncURL = url;
    } else {
        /* FIX: Re-enable this functionality
        if (_syncPushCheckbox.state) {
            NSLog(@"**** Pushing to <%@> ...", url);
            [self observeReplication: [_database pushToDatabaseAtURL: url]];
        }
        if (_syncPullCheckbox.state) {
            NSLog(@"**** Pulling from <%@> ...", url);
            [self observeReplication: [_database pullFromDatabaseAtURL: url]];
        }
         */
    }
}


- (void) resetReplication: (CBLReplication*)repl {
    [repl setValue: @YES ofProperty: @"reset"];
    [repl restart];
}

- (IBAction) resetSync: (id)sender {
    for (CBLReplication* repl in _database.allReplications)
        [self resetReplication: repl];
}


#pragma mark - SYNC:


- (NSURL*) syncURL {
    NSString* urlStr = [[NSUserDefaults standardUserDefaults] stringForKey: @"SyncURL"];
    return urlStr ? [NSURL URLWithString: urlStr] : nil;
}

- (void) setSyncURL:(NSURL *)url {
    NSURL* currentURL = self.syncURL;
    if (url != currentURL && ![url isEqual: currentURL]) {
        [[NSUserDefaults standardUserDefaults] setObject: url.absoluteString
                                                  forKey: @"SyncURL"];
        [self startContinuousSyncWith: url];
    }
}


- (void) observeReplication: (CBLReplication*)repl {
    [repl addObserver: self forKeyPath: @"completedChangesCount" options: 0 context: NULL];
    [repl addObserver: self forKeyPath: @"changesCount" options: 0 context: NULL];
    [repl addObserver: self forKeyPath: @"lastError" options: 0 context: NULL];
    [repl addObserver: self forKeyPath: @"mode" options: 0 context: NULL];
}

- (void) stopObservingReplication: (CBLReplication*)repl {
    [repl removeObserver: self forKeyPath: @"completedChangesCount"];
    [repl removeObserver: self forKeyPath: @"changesCount"];
    [repl removeObserver: self forKeyPath: @"lastError"];
    [repl removeObserver: self forKeyPath: @"mode"];
}


- (void) startContinuousSyncWith: (NSURL*)otherDbURL {
#ifdef ENABLE_REPLICATION
    if (_pull)
        [self stopObservingReplication: _pull];
    if (_push)
        [self stopObservingReplication: _push];
    NSArray* repls = [_database replicationsWithURL: otherDbURL exclusively: YES];
    _pull = repls[0];
    _push = repls[1];
    _pull.continuous = _push.continuous = YES;
    [self observeReplication: _pull];
    [self observeReplication: _push];
    [_pull start];
    [_push start];
    
    _syncHostField.stringValue = otherDbURL ? $sprintf(@"⇄ %@", otherDbURL.host) : @"";
#endif
}


- (void) updateSyncStatusView {
#ifdef ENABLE_REPLICATION
    int value;
    NSString* tooltip = nil;
    if (_pull.lastError) {
        value = 3;  // red
        tooltip = _pull.lastError.localizedDescription;
    } else if (_push.lastError) {
        value = 3;  // red
        tooltip = _push.lastError.localizedDescription;
    } else switch(MAX(_pull.mode, _push.mode)) {
        case kCBLReplicationStopped:
            value = 3; 
            tooltip = @"Sync stopped";
            break;  // red
        case kCBLReplicationOffline:
            value = 2;  // yellow
            tooltip = @"Offline";
            break;
        case kCBLReplicationIdle:
            value = 0;
            tooltip = @"Everything's in sync!";
            break;
        case kCBLReplicationActive:
            value = 1;
            tooltip = @"Syncing data...";
            break;
        default:
            NSAssert(NO, @"Illegal mode");
            break;
    }
    _syncStatusView.intValue = value;
    _syncStatusView.toolTip = tooltip;
    NSLog(@"SYNC status: %d, %@", value, tooltip);
#endif
}


#ifdef ENABLE_REPLICATION
- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object 
                         change:(NSDictionary *)change context:(void *)context
{
    CBLReplication* repl = object;
    NSLog(@"SYNC mode=%d", repl.mode);
    if ([keyPath isEqualToString: @"completed"] || [keyPath isEqualToString: @"total"]) {
        if (repl == _pull || repl == _push) {
            unsigned completed = _pull.completedChangesCount + _push.completedChangesCount;
            unsigned total = _pull.changesCount + _push.changesCount;
            NSLog(@"SYNC progress: %u / %u", completed, total);
            if (total > 0 && completed < total) {
                [_syncProgress setDoubleValue: (completed / (double)total)];
            } else {
                [_syncProgress setDoubleValue: 0.0];
            }
        }
    } else if ([keyPath isEqualToString: @"mode"]) {
        [self updateSyncStatusView];
    } else if ([keyPath isEqualToString: @"error"]) {
        [self updateSyncStatusView];
        if (repl.lastError) {
            NSLog(@"SYNC error: %@", repl.lastError);
            NSAlert* alert = [NSAlert alertWithMessageText: @"Replication failed"
                                             defaultButton: nil
                                           alternateButton: nil
                                               otherButton: nil
                                 informativeTextWithFormat: @"Replication with %@ failed.\n\n %@",
                              repl.remoteURL, repl.lastError.localizedDescription];
            [alert beginSheetModalForWindow: _window
                              modalDelegate: nil didEndSelector: NULL contextInfo: NULL];
        }
    } else if ([keyPath isEqualToString: @"running"]) {
        if (repl != _push && repl != _pull) {
            // end of a 1-shot replication
            [self stopObservingReplication: repl];
        }
    }
}
#endif


#pragma mark - JS MAP/REDUCE FUNCTIONS:

#ifdef FOR_TESTING_PURPOSES

// These map/reduce functions are used in the CouchbaseLite 'basics.js' unit tests. By recognizing them
// here and returning equivalent native blocks, we can run those tests.

- (CBLMapBlock) compileMapFunction: (NSString*)mapSource language:(NSString *)language {
    if (![language isEqualToString: @"javascript"])
        return NULL;
    CBLMapBlock mapBlock = NULL;
    if ([mapSource isEqualToString: @"(function (doc) {if (doc.a == 4) {emit(null, doc.b);}})"]) {
        mapBlock = MAPBLOCK({
            if ([doc[@"a"] isEqual: @4])
                emit(nil, doc[@"b"]);
        });
    } else if ([mapSource isEqualToString: @"(function (doc) {emit(doc.foo, null);})"] ||
               [mapSource isEqualToString: @"function(doc) { emit(doc.foo, null); }"]) {
        mapBlock =  MAPBLOCK({
            emit(doc[@"foo"], nil);
        });
    }
    return [mapBlock copy];
}


- (CBLReduceBlock) compileReduceFunction: (NSString*)reduceSource language:(NSString *)language {
    if (![language isEqualToString: @"javascript"])
        return NULL;
    CBLReduceBlock reduceBlock = NULL;
    if ([reduceSource isEqualToString: @"(function (keys, values) {return sum(values);})"]) {
        reduceBlock = ^(NSArray* keys, NSArray* values, BOOL rereduce) {
            return [CBLView totalValues: values];
        };
    }
    return [reduceBlock copy];
}

#endif


#pragma mark HIGHLIGHTING NEW ITEMS:


- (void)tableView:(NSTableView *)tableView
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row 
{
    NSColor* bg = nil;

    NSArray* items = _tableController.arrangedObjects;
    if (row >= (NSInteger)items.count)
        return;                 // Don't know why I get called on illegal rows, but it happens...
    CBLModel* item = items[row];
    NSTimeInterval changedFor = item.timeSinceExternallyChanged;
    if (changedFor > 0 && changedFor < kChangeGlowDuration) {
        float fraction = (float)(1.0 - changedFor / kChangeGlowDuration);
        if (YES || [cell isKindOfClass: [NSButtonCell class]])
            bg = [[NSColor controlBackgroundColor] blendedColorWithFraction: fraction 
                                                        ofColor: [NSColor yellowColor]];
        else
            bg = [[NSColor yellowColor] colorWithAlphaComponent: fraction];
        
        if (!_glowing) {
            _glowing = YES;
            MYAfterDelay(0.1, ^{
                _glowing = NO;
                [_table setNeedsDisplay: YES];
            });
        }
    }
    
    [cell setBackgroundColor: bg];
    [cell setDrawsBackground: (bg != nil)];
}


@end
