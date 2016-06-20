//
//  DemoAppController.h
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

#import <Cocoa/Cocoa.h>
@class CBLDatabase, CBLReplication, DemoQuery;


/** Generic application delegate for simple Mac OS CouchbaseLite demo apps.
    The name of the (local) database to use should be added to the app's Info.plist
    under the 'DemoDatabase' key. */
@interface DemoAppController : NSObject
{
    IBOutlet NSWindow* _window;
    IBOutlet NSTableView* _table;
    IBOutlet NSArrayController* _tableController;
    IBOutlet NSProgressIndicator* _syncProgress;
    IBOutlet NSTextField* _syncHostField;
    IBOutlet NSLevelIndicator* _syncStatusView;
    
    IBOutlet NSPanel* _syncConfigSheet;
    IBOutlet NSTextField* _syncURLField;
    IBOutlet NSButtonCell* _syncPushCheckbox, *_syncPullCheckbox;
    
    CBLDatabase* _database;
    DemoQuery* _query;
    BOOL _syncConfiguringDefault;
    CBLReplication *_pull, *_push;
    BOOL _glowing;
}

@property (retain) DemoQuery* query;

- (IBAction) addItem:(id)sender;
- (IBAction) compact: (id)sender;
- (IBAction) configureSync: (id)sender;
- (IBAction) dismissSyncConfigSheet:(id)sender;
- (IBAction) resetSync: (id)sender;
- (IBAction) fakeOpenIDLogin: (id)sender;

@property (retain) NSURL* syncURL;

- (void) startContinuousSyncWith: (NSURL*)otherDbURL;

@end
