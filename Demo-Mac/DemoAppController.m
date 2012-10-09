//
//  DemoAppController.m
//  CouchCocoa
//
//  Created by Jens Alfke on 6/1/11.
//  Copyright (c) 2011 Couchbase, Inc, Inc.
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
#import "Test.h"
#import "MYBlockUtils.h"
#import <CouchCocoa/CouchCocoa.h>
#import <CouchCocoa/CouchTouchDBServer.h>
#import <CouchCocoa/CouchDesignDocument_Embedded.h>

#define FOR_TESTING_PURPOSES
#ifdef FOR_TESTING_PURPOSES
#import <TouchDBListener/TDListener.h>
@interface DemoAppController () <TDViewCompiler>
@end
static TDListener* sListener;
#endif


#define kChangeGlowDuration 3.0


int main (int argc, const char * argv[]) {
    RunTestCases(argc,argv);
    return NSApplicationMain(argc, argv);
}


@implementation DemoAppController


@synthesize query = _query;


- (void) applicationDidFinishLaunching: (NSNotification*)n {
    //gRESTLogLevel = kRESTLogRequestURLs;
    gCouchLogLevel = 1;
    
    NSDictionary* bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString* dbName = bundleInfo[@"DemoDatabase"];
    if (!dbName) {
        NSLog(@"FATAL: Please specify a CouchDB database name in the app's Info.plist under the 'DemoDatabase' key");
        exit(1);
    }
    
    CouchTouchDBServer* server = [CouchTouchDBServer sharedInstance];
    NSAssert(!server.error, @"Error initializing TouchDB: %@", server.error);

    _database = [[server databaseNamed: dbName] retain];
    
    RESTOperation* op = [_database create];
    if (![op wait]) {
        NSAssert(op.error.code == 412, @"Error creating db: %@", op.error);
    }
    
    // Create a 'view' containing list items sorted by date:
    CouchDesignDocument* design = [_database designDocumentWithName: @"default"];
    [design defineViewNamed: @"byDate" mapBlock: MAPBLOCK({
        id date = doc[@"created_at"];
        if (date) emit(date, doc);
    }) version: @"1.0"];
    
    // and a validation function requiring parseable dates:
    design.validationBlock = VALIDATIONBLOCK({
        if (newRevision.deleted)
            return YES;
        id date = newRevision[@"created_at"];
        if (date && ! [RESTBody dateWithJSONObject: date]) {
            context.errorMessage = [@"invalid date " stringByAppendingString: date];
            return NO;
        }
        return YES;
    });
    
    // And why not a filter, just to allow some simple testing of filtered _changes.
    // For example, try curl 'http://localhost:8888/demo-shopping/_changes?filter=default/checked'
    [design defineFilterNamed: @"checked" block: FILTERBLOCK({
        return [revision[@"check"] boolValue];
    })];

    
    CouchQuery* q = [design queryViewNamed: @"byDate"];
    q.descending = YES;
    self.query = [[[DemoQuery alloc] initWithQuery: q] autorelease];
    self.query.modelClass =_tableController.objectClass;
    
    // Start watching any persistent replications already configured:
    [self startContinuousSyncWith: self.syncURL];
    
#ifdef FOR_TESTING_PURPOSES
    // Start a listener socket:
    [server tellTDServer: ^(TDServer* tdServer) {
        // Register support for handling certain JS functions used in the CouchDB unit tests:
        [TDView setCompiler: self];
        
        sListener = [[TDListener alloc] initWithTDServer: tdServer port: 8888];
        [sListener start];
    }];

#endif
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
        /* FIX: Re-enable this functionality once CouchReplication/CouchPersistentReplication
                 are merged
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


- (void) observeReplication: (CouchPersistentReplication*)repl {
    [repl addObserver: self forKeyPath: @"completed" options: 0 context: NULL];
    [repl addObserver: self forKeyPath: @"total" options: 0 context: NULL];
    [repl addObserver: self forKeyPath: @"error" options: 0 context: NULL];
    [repl addObserver: self forKeyPath: @"mode" options: 0 context: NULL];
}

- (void) stopObservingReplication: (CouchPersistentReplication*)repl {
    [repl removeObserver: self forKeyPath: @"completed"];
    [repl removeObserver: self forKeyPath: @"total"];
    [repl removeObserver: self forKeyPath: @"error"];
    [repl removeObserver: self forKeyPath: @"mode"];
}

- (void) forgetReplication: (CouchPersistentReplication**)repl {
    if (*repl) {
        [self stopObservingReplication: *repl];
        [*repl release];
        *repl = nil;
    }
}


- (void) startContinuousSyncWith: (NSURL*)otherDbURL {
    [self forgetReplication: &_pull];
    [self forgetReplication: &_push];
    
    NSArray* repls = [_database replicateWithURL: otherDbURL exclusively: YES];
    _pull = [repls[0] retain];
    _push = [repls[1] retain];
    [self observeReplication: _pull];
    [self observeReplication: _push];
    
    _syncHostField.stringValue = otherDbURL ? $sprintf(@"⇄ %@", otherDbURL.host) : @"";
}


- (void) updateSyncStatusView {
    int value;
    NSString* tooltip = nil;
    if (_pull.error) {
        value = 3;  // red
        tooltip = _pull.error.localizedDescription;
    } else if (_push.error) {
        value = 3;  // red
        tooltip = _push.error.localizedDescription;
    } else switch(MAX(_pull.mode, _push.mode)) {
        case kCouchReplicationStopped:
            value = 3; 
            tooltip = @"Sync stopped";
            break;  // red
        case kCouchReplicationOffline:
            value = 2;  // yellow
            tooltip = @"Offline";
            break;
        case kCouchReplicationIdle:
            value = 0;
            tooltip = @"Everything's in sync!";
            break;
        case kCouchReplicationActive:
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
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object 
                         change:(NSDictionary *)change context:(void *)context
{
    CouchPersistentReplication* repl = object;
    NSLog(@"SYNC mode=%d, state=%d", repl.mode, repl.state);
    if ([keyPath isEqualToString: @"completed"] || [keyPath isEqualToString: @"total"]) {
        if (repl == _pull || repl == _push) {
            unsigned completed = _pull.completed + _push.completed;
            unsigned total = _pull.total + _push.total;
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
        if (repl.error) {
            NSLog(@"SYNC error: %@", repl.error);
            NSAlert* alert = [NSAlert alertWithMessageText: @"Replication failed"
                                             defaultButton: nil
                                           alternateButton: nil
                                               otherButton: nil
                                 informativeTextWithFormat: @"Replication with %@ failed.\n\n %@",
                              repl.remoteURL, repl.error.localizedDescription];
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


#pragma mark - JS MAP/REDUCE FUNCTIONS:

#ifdef FOR_TESTING_PURPOSES

// These map/reduce functions are used in the CouchDB 'basics.js' unit tests. By recognizing them
// here and returning equivalent native blocks, we can run those tests.

- (TDMapBlock) compileMapFunction: (NSString*)mapSource language:(NSString *)language {
    if (![language isEqualToString: @"javascript"])
        return NULL;
    TDMapBlock mapBlock = NULL;
    if ([mapSource isEqualToString: @"(function (doc) {if (doc.a == 4) {emit(null, doc.b);}})"]) {
        mapBlock = ^(NSDictionary* doc, TDMapEmitBlock emit) {
            if ([doc[@"a"] isEqual: @4])
                emit(nil, doc[@"b"]);
        };
    } else if ([mapSource isEqualToString: @"(function (doc) {emit(doc.foo, null);})"] ||
               [mapSource isEqualToString: @"function(doc) { emit(doc.foo, null); }"]) {
        mapBlock = ^(NSDictionary* doc, TDMapEmitBlock emit) {
            emit(doc[@"foo"], nil);
        };
    }
    return [[mapBlock copy] autorelease];
}


- (TDReduceBlock) compileReduceFunction: (NSString*)reduceSource language:(NSString *)language {
    if (![language isEqualToString: @"javascript"])
        return NULL;
    TDReduceBlock reduceBlock = NULL;
    if ([reduceSource isEqualToString: @"(function (keys, values) {return sum(values);})"]) {
        reduceBlock = ^(NSArray* keys, NSArray* values, BOOL rereduce) {
            return [TDView totalValues: values];
        };
    }
    return [[reduceBlock copy] autorelease];
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
    CouchModel* item = items[row];
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
