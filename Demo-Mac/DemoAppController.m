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
    
    // Create a 'view' containing list items sorted by date:
    CouchDesignDocument* design = [_database designDocumentWithName: @"default"];
    [design defineViewNamed: @"byDate" mapBlock: MAPBLOCK({
        id date = [doc objectForKey: @"created_at"];
        if (date) emit(date, doc);
    }) version: @"1.0"];
    
    // and a validation function requiring parseable dates:
    design.validationBlock = VALIDATIONBLOCK({
        if (newRevision.deleted)
            return YES;
        id date = [newRevision.properties objectForKey: @"created_at"];
        if (date && ! [RESTBody dateWithJSONObject: date]) {
            context.errorMessage = [@"invalid date " stringByAppendingString: date];
            return NO;
        }
        return YES;
    });
    
    // And why not a filter, just to allow some simple testing of filtered _changes.
    // For example, try curl 'http://localhost:8888/demo-shopping/_changes?filter=default/checked'
    [design defineFilterNamed: @"checked" block: FILTERBLOCK({
        return [revision.properties objectForKey: @"check"] == $true;
    })];

    
    CouchQuery* q = [design queryViewNamed: @"byDate"];
    q.descending = YES;
    self.query = [[[DemoQuery alloc] initWithQuery: q] autorelease];
    self.query.modelClass =_tableController.objectClass;
    
    // Enable continuous sync:
    [self startContinuousSyncWith: self.syncURL];
    
#ifdef FOR_TESTING_PURPOSES
    // Start a listener socket:
    sListener = [[TDListener alloc] initWithTDServer: server.touchServer port: 8888];
    [sListener start];

    // Register support for handling certain JS functions used in the CouchDB unit tests:
    [TDView setCompiler: self];
#endif
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
    }
}


#pragma mark - JS MAP/REDUCE FUNCTIONS:

#ifdef FOR_TESTING_PURPOSES

// These map/reduce functions are used in the CouchDB 'basics.js' unit tests. By recognizing them
// here and returning equivalent native blocks, we can run those tests.

- (TDMapBlock) compileMapFunction: (NSString*)mapSource language:(NSString *)language {
    if (!$equal(language, @"javascript"))
        return NULL;
    TDMapBlock mapBlock = NULL;
    if ($equal(mapSource, @"(function (doc) {if (doc.a == 4) {emit(null, doc.b);}})")) {
        mapBlock = ^(NSDictionary* doc, TDMapEmitBlock emit) {
            if ($equal([doc objectForKey: @"a"], $object(4)))
                emit(nil, [doc objectForKey: @"b"]);
        };
    } else if ($equal(mapSource, @"(function (doc) {emit(doc.foo, null);})") ||
               $equal(mapSource, @"function(doc) { emit(doc.foo, null); }")) {
        mapBlock = ^(NSDictionary* doc, TDMapEmitBlock emit) {
            emit([doc objectForKey: @"foo"], nil);
        };
    }
    return [[mapBlock copy] autorelease];
}


- (TDReduceBlock) compileReduceFunction: (NSString*)reduceSource language:(NSString *)language {
    if (!$equal(language, @"javascript"))
        return NULL;
    TDReduceBlock reduceBlock = NULL;
    if ($equal(reduceSource, @"(function (keys, values) {return sum(values);})")) {
        reduceBlock = ^(NSArray* keys, NSArray* values, BOOL rereduce) {
            return [TDView totalValues: values];
        };
    }
    return [[reduceBlock copy] autorelease];
}

#endif


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
