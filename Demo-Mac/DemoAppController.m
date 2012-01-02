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
#import "TouchDB.h"
#import <TouchDBListener/TDListener.h>
#import <CouchCocoa/CouchCocoa.h>
#import <CouchCocoa/CouchTouchDBServer.h>


#define kChangeGlowDuration 3.0


int main (int argc, const char * argv[]) {
    RunTestCases(argc,argv);
    return NSApplicationMain(argc, argv);
}


static TDListener* sListener;


@implementation DemoAppController


@synthesize query = _query;


- (void) applicationDidFinishLaunching: (NSNotification*)n {
    //gRESTLogLevel = kRESTLogRequestURLs;
    //gCouchLogLevel = 1;
    
    NSDictionary* bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString* dbName = [bundleInfo objectForKey: @"DemoDatabase"];
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
    
    // Create a CouchDB 'view' containing list items sorted by date
    TDDatabase* tdb = [server.touchServer existingDatabaseNamed: dbName];
    NSAssert(tdb, @"Failed to open or create TouchDB database");
    [[tdb viewNamed: @"default/byDate"] setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        id date = [doc objectForKey: @"created_at"];
        if (date) emit(date, doc);
    } reduceBlock: NULL version: @"1"];
        
    // ...and a validation function requiring parseable dates:
    [tdb addValidation: ^(TDRevision* newRevision, id<TDValidationContext>context) {
        if (newRevision.deleted)
            return YES;
        id date = [newRevision.properties objectForKey: @"created_at"];
        if (date && ! [RESTBody dateWithJSONObject: date]) {
            context.errorMessage = [@"invalid date " stringByAppendingString: date];
            return NO;
        }
        return YES;
    }];
    
    // And why not a filter, just to allow some simple testing of filtered _changes.
    // For example, try curl -i 'http://localhost:8888/demo-shopping/_changes?filter=checked'
    [tdb defineFilter: @"checked" asBlock: ^BOOL(TDRevision *revision) {
        return [revision.properties objectForKey: @"check"] == $true;
    }];

    
    CouchQuery* q = [[_database designDocumentWithName: @"default"] queryViewNamed: @"byDate"];
    q.descending = YES;
    self.query = [[[DemoQuery alloc] initWithQuery: q] autorelease];
    self.query.modelClass =_tableController.objectClass;
    
    // Enable continuous sync:
    [self startContinuousSyncWith: self.syncURL];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(replicationProgressChanged:)
                                                 name: TDReplicatorProgressChangedNotification
                                               object: nil];
    
    // Start a listener socket:
    sListener = [[TDListener alloc] initWithTDServer: server.touchServer port: 8888];
    [sListener start];
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


- (IBAction) configureSync: (id)sender {
    _syncURLField.objectValue = self.syncURL.absoluteString;
    [NSApp beginSheet: _syncConfigSheet modalForWindow: _window
        modalDelegate: self
       didEndSelector:@selector(configureSyncFinished:returnCode:)
          contextInfo: NULL];
}

- (IBAction) dismissSyncConfigSheet:(id)sender {
    NSInteger returnCode = [sender tag];
    if (returnCode == NSOKButton 
            && _syncURLField.stringValue.length > 0 && !self.currentURLFromField) {
        NSBeep();
        return;
    }
    [NSApp endSheet: _syncConfigSheet returnCode: returnCode];
}

- (void) configureSyncFinished:(NSWindow *)sheet returnCode:(NSInteger)returnCode {
    [sheet orderOut: self];
    if (returnCode == NSOKButton)
        self.syncURL = self.currentURLFromField;
}


- (void) stopReplication: (CouchReplication**)repl {
    [*repl removeObserver: self forKeyPath: @"completed"];
    [*repl stop];
    [*repl release];
    *repl = nil;
}


- (void) startContinuousSyncWith: (NSURL*)otherDbURL {
    [self stopReplication: &_pull];
    [self stopReplication: &_push];
    if (otherDbURL) {
        _pull = [[_database pullFromDatabaseAtURL: otherDbURL options: kCouchReplicationContinuous]
                    retain];
        [_pull addObserver: self forKeyPath: @"completed" options: 0 context: NULL];

        _push = [[_database pushToDatabaseAtURL: otherDbURL options: kCouchReplicationContinuous]
                    retain];
        [_push addObserver: self forKeyPath: @"completed" options: 0 context: NULL];
    }
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object 
                         change:(NSDictionary *)change context:(void *)context
{
    if (object == _pull || object == _push) {
        unsigned completed = _pull.completed + _push.completed;
        unsigned total = _pull.total + _push.total;
        NSLog(@"SYNC progress: %u / %u", completed, total);
        if (total > 0 && completed < total) {
            [_syncProgress setDoubleValue: (completed / (double)total)];
        } else {
            [_syncProgress setDoubleValue: 0.0];
        }
        _database.server.activityPollInterval = 0;   // I use notifications instead
    }
}


- (void) replicationProgressChanged: (NSNotification*)n {
    // This is called on the TouchDB background thread, so redispatch to the main thread:
    [_database.server performSelectorOnMainThread: @selector(checkActiveTasks)
                                       withObject: nil waitUntilDone: NO];
}


#pragma mark HIGHLIGHTING NEW ITEMS:


- (void) updateTableGlows {
    _glowing = NO;
    [_table setNeedsDisplay: YES];
}


- (void)tableView:(NSTableView *)tableView
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row 
{
    NSColor* bg = nil;

    NSArray* items = _tableController.arrangedObjects;
    if (row >= (NSInteger)items.count)
        return;                 // Don't know why I get called on illegal rows, but it happens...
    CouchModel* item = [items objectAtIndex: row];
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
            [self performSelector: @selector(updateTableGlows) withObject: nil afterDelay: 0.1];
        }
    }
    
    [cell setBackgroundColor: bg];
    [cell setDrawsBackground: (bg != nil)];
}


@end
