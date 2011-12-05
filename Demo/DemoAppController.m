//
//  DemoAppController.m
//  CouchCocoa
//
//  Created by Jens Alfke on 6/1/11.
//  Copyright 2011 Couchbase, Inc.
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
#import "ToyDB.h"
#import "ToyServer.h"
#import "ToyProtocol.h"
#import "ToyPuller.h"
#import <CouchCocoa/CouchCocoa.h>


#define kChangeGlowDuration 3.0


int main (int argc, const char * argv[]) {
    RunTestCases(argc,argv);
    return NSApplicationMain(argc, argv);
}


@implementation DemoAppController


@synthesize query = _query;


- (void) applicationDidFinishLaunching: (NSNotification*)n {
    gRESTLogLevel = kRESTLogRequestURLs;
    gCouchLogLevel = 3;//TEMP
    
    NSDictionary* bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString* dbName = [bundleInfo objectForKey: @"DemoDatabase"];
    if (!dbName) {
        NSLog(@"FATAL: Please specify a CouchDB database name in the app's Info.plist under the 'DemoDatabase' key");
        exit(1);
    }

#if 0
    CouchServer *server = [[CouchServer alloc] init];
#else
    ToyServer* toyServer = [[ToyServer alloc] initWithDirectory: @"/tmp/ShoppingDemo" error: nil];
    NSAssert(toyServer, @"Couldn't create ToyServer");
    [ToyProtocol setServer: toyServer];
    NSURL* url = [NSURL URLWithString: @"toy:///"];
    CouchServer *server = [[CouchServer alloc] initWithURL: url];
#endif
    _database = [[server databaseNamed: dbName] retain];
    [server release];
    
    RESTOperation* op = [_database create];
    if (![op wait]) {
        NSAssert(op.error.code == 412, @"Error creating db: %@", op.error);
    }
    
    CouchQuery* q = [_database getAllDocuments];
    q.descending = YES;
    self.query = [[[DemoQuery alloc] initWithQuery: q] autorelease];
    self.query.modelClass =_tableController.objectClass;
    
    // Enable continuous sync:
    NSString* otherDbURL = [bundleInfo objectForKey: @"SyncDatabaseURL"];
    if (otherDbURL.length > 0)
        [self startContinuousSyncWith: [NSURL URLWithString: otherDbURL]];
}


- (void) startContinuousSyncWith: (NSURL*)otherDbURL {
#if 1
    ToyDB* db = [[ToyProtocol server] databaseNamed: _database.relativePath];
    _puller = [[ToyPuller alloc] initWithDB: db remote: otherDbURL];
#else
    _pull = [[_database pullFromDatabaseAtURL: otherDbURL
                                      options: kCouchReplicationContinuous] retain];
    _push = [[_database pushToDatabaseAtURL: otherDbURL
                                    options: kCouchReplicationContinuous] retain];
#endif
}


- (IBAction) startSync:(id)sender {
    [_puller start];
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
        float fraction = 1.0 - changedFor / kChangeGlowDuration;
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
