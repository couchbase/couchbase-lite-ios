//
//  RootViewController.m
//  Couchbase Mobile
//
//  Created by Jan Lehnardt on 27/11/2010.
//  Copyright 2011-2013 Couchbase, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations under
// the License.
//

#import "RootViewController.h"
#import "ConfigViewController.h"
#import "DemoAppDelegate.h"

#import "CouchbaseLite.h"
#import "CBLView+Internal.h"
#import "CBLDatabase+Insertion.h"
#import "CBLJSON.h"


@interface RootViewController ()
@property(nonatomic, strong)CBLDatabase *database;
@property(nonatomic, strong)NSURL* remoteSyncURL;
@end


@implementation RootViewController


@synthesize dataSource;
@synthesize database;
@synthesize tableView;
@synthesize remoteSyncURL;


#pragma mark - View lifecycle


- (void)viewDidLoad {
    [super viewDidLoad];

    if (!database)
        return;     // App controller failed to load database; probably displaying fatal alert now

    UIBarButtonItem* deleteButton = [[UIBarButtonItem alloc] initWithTitle: @"Clean"
                                                            style:UIBarButtonItemStylePlain
                                                           target: self 
                                                           action: @selector(deleteCheckedItems:)];
    self.navigationItem.leftBarButtonItem = deleteButton;
    
    [self showSyncButton];
    
    [self.tableView setBackgroundView:nil];
    [self.tableView setBackgroundColor:[UIColor clearColor]];
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        [addItemBackground setFrame:CGRectMake(45, 8, 680, 44)];
        [addItemTextField setFrame:CGRectMake(56, 8, 665, 43)];
    }

    // Create a query sorted by descending date, i.e. newest items first:
    NSAssert(database!=nil, @"Not hooked up to database yet");
    CBLLiveQuery* query = [[[database viewNamed: @"byDate"] createQuery] asLiveQuery];
    query.descending = YES;
    
    self.dataSource.query = query;
    self.dataSource.labelProperty = @"text";    // Document property to display in the cell label

    [self updateSyncURL];
}


- (void)dealloc {
    [self forgetSync];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear: animated];
    // Check for changes after returning from the sync config view:
    [self updateSyncURL];
}


- (void)useDatabase:(CBLDatabase*)theDatabase {
    self.database = theDatabase;
    
    // Create a 'view' containing list items sorted by date:
    [[theDatabase viewNamed: @"byDate"] setMapBlock: MAPBLOCK({
        id date = [doc objectForKey: @"created_at"];
        if (date) emit(date, doc);
    }) reduceBlock: nil version: @"1.1"];
    
    
    // and a validation function requiring parseable dates:
    [theDatabase setValidationNamed: @"created_at" asBlock: VALIDATIONBLOCK({
        if (newRevision.isDeletion)
            return YES;
        id date = [newRevision.properties objectForKey: @"created_at"];
        if (date && ! [CBLJSON dateWithJSONObject: date]) {
            context.errorMessage = [@"invalid date " stringByAppendingString: [date description]];
            return NO;
        }
        return YES;
    })];
}


- (void)showErrorAlert: (NSString*)message forError: (NSError*)error {
    NSLog(@"%@: error=%@", message, error);
    [(DemoAppDelegate*)[[UIApplication sharedApplication] delegate] 
        showAlert: message error: error fatal: NO];
}


#pragma mark - Couch table source delegate


// Customize the appearance of table view cells.
- (void)couchTableSource:(CBLUITableSource*)source
             willUseCell:(UITableViewCell*)cell
                  forRow:(CBLQueryRow*)row
{
    // Set the cell background and font:
    static UIColor* kBGColor;
    if (!kBGColor)
        kBGColor = [UIColor colorWithPatternImage: [UIImage imageNamed:@"item_background"]];
    cell.backgroundColor = kBGColor;
    cell.selectionStyle = UITableViewCellSelectionStyleGray;

    cell.textLabel.font = [UIFont fontWithName: @"Helvetica" size:18.0];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    
    // Configure the cell contents. Our view function (see above) copies the document properties
    // into its value, so we can read them from there without having to load the document.
    // cell.textLabel.text is already set, thanks to setting up labelProperty above.
    NSDictionary* properties = row.value;
    BOOL checked = [[properties objectForKey:@"check"] boolValue];
    cell.textLabel.textColor = checked ? [UIColor grayColor] : [UIColor blackColor];
    cell.imageView.image = [UIImage imageNamed:
            (checked ? @"list_area___checkbox___checked" : @"list_area___checkbox___unchecked")];
}


#pragma mark - Table view delegate


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CBLQueryRow *row = [self.dataSource rowAtIndex:indexPath.row];
    CBLDocument *doc = [row document];

    // Toggle the document's 'checked' property:
    NSMutableDictionary *docContent = [doc.properties mutableCopy];
    BOOL wasChecked = [[docContent valueForKey:@"check"] boolValue];
    [docContent setObject:[NSNumber numberWithBool:!wasChecked] forKey:@"check"];

    // Save changes:
    NSError* error;
    if (![doc.currentRevision createRevisionWithProperties: docContent error: &error]) {
        [self showErrorAlert: @"Failed to update item" forError: error];
    }
}


#pragma mark - Editing:


- (NSArray*)checkedDocuments {
    // If there were a whole lot of documents, this would be more efficient with a custom query.
    NSMutableArray* checked = [NSMutableArray array];
    for (CBLQueryRow* row in self.dataSource.rows) {
        CBLDocument* doc = row.document;
        if ([[doc.properties valueForKey:@"check"] boolValue])
            [checked addObject: doc];
    }
    return checked;
}


- (IBAction)deleteCheckedItems:(id)sender {
    NSUInteger numChecked = self.checkedDocuments.count;
    if (numChecked == 0)
        return;
    NSString* message = [NSString stringWithFormat: @"Are you sure you want to remove the %lu"
                                                     " checked-off item%@?",
                                                     (unsigned long)numChecked,
                                                     (numChecked==1 ? @"" : @"s")];
    UIAlertView* alert = [[UIAlertView alloc] initWithTitle: @"Remove Completed Items?"
                                                    message: message
                                                   delegate: self
                                          cancelButtonTitle: @"Cancel"
                                          otherButtonTitles: @"Remove", nil];
    [alert show];
}


- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0)
        return;
    [dataSource deleteDocuments: self.checkedDocuments error: NULL];
}


#pragma mark - UITextField delegate


- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
    [addItemBackground setImage:[UIImage imageNamed:@"textfield___inactive.png"]];

	return YES;
}


- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [addItemBackground setImage:[UIImage imageNamed:@"textfield___active.png"]];
}


-(void)textFieldDidEndEditing:(UITextField *)textField {
    // Get the name of the item from the text field:
	NSString *text = addItemTextField.text;
    if (text.length == 0) {
        return;
    }
    [addItemTextField setText:nil];

    // Create the new document's properties:
	NSDictionary *inDocument = [NSDictionary dictionaryWithObjectsAndKeys:text, @"text",
                                [NSNumber numberWithBool:NO], @"check",
                                [CBLJSON JSONObjectWithDate: [NSDate date]], @"created_at",
                                nil];

    // Save the document:
    CBLDocument* doc = [database createDocument];
    NSError* error;
    if (![doc putProperties: inDocument error: &error]) {
        [self showErrorAlert: @"Couldn't save new item" forError: error];
    }
}


#pragma mark - SYNC:


- (IBAction)configureSync:(id)sender {
    UINavigationController* navController = (UINavigationController*)self.parentViewController;
    ConfigViewController* controller = [[ConfigViewController alloc] init];
    [navController pushViewController: controller animated: YES];
}


- (void)updateSyncURL {
    if (!self.database)
        return;
    NSURL* newRemoteURL = nil;
    NSString *syncpoint = [[NSUserDefaults standardUserDefaults] objectForKey:@"syncpoint"];
    if (syncpoint.length > 0)
        newRemoteURL = [NSURL URLWithString:syncpoint];
    
    [self forgetSync];
    
    NSArray* repls = [self.database replicationsWithURL: newRemoteURL exclusively: YES];
    if (repls) {
        _pull = [repls objectAtIndex: 0];
        _push = [repls objectAtIndex: 1];
        _pull.continuous = _push.continuous = YES;
        _pull.persistent = _push.persistent = YES;
        NSNotificationCenter* nctr = [NSNotificationCenter defaultCenter];
        [nctr addObserver: self selector: @selector(replicationProgress:)
                     name: kCBLReplicationChangeNotification object: _pull];
        [nctr addObserver: self selector: @selector(replicationProgress:)
                     name: kCBLReplicationChangeNotification object: _push];
        [_pull start];
        [_push start];
    }
}


- (void) forgetSync {
    NSNotificationCenter* nctr = [NSNotificationCenter defaultCenter];
    if (_pull) {
        [nctr removeObserver: self name: nil object: _pull];
        _pull = nil;
    }
    if (_push) {
        [nctr removeObserver: self name: nil object: _push];
        _push = nil;
    }
}


- (void)showSyncButton {
    if (!showingSyncButton) {
        showingSyncButton = YES;
        UIBarButtonItem* syncButton =
                [[UIBarButtonItem alloc] initWithTitle: @"Configure"
                                                 style:UIBarButtonItemStylePlain
                                                target: self 
                                                action: @selector(configureSync:)];
        self.navigationItem.rightBarButtonItem = syncButton;
    }
}


- (void)showSyncStatus {
    if (showingSyncButton) {
        showingSyncButton = NO;
        if (!progress) {
            progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
            CGRect frame = progress.frame;
            frame.size.width = self.view.frame.size.width / 4.0f;
            progress.frame = frame;
        }
        UIBarButtonItem* progressItem = [[UIBarButtonItem alloc] initWithCustomView:progress];
        progressItem.enabled = NO;
        self.navigationItem.rightBarButtonItem = progressItem;
    }
}


- (void) replicationProgress: (NSNotificationCenter*)n {
    if (_pull.mode == kCBLReplicationActive || _push.mode == kCBLReplicationActive) {
        unsigned completed = _pull.completedChangesCount + _push.completedChangesCount;
        unsigned total = _pull.changesCount + _push.changesCount;
        NSLog(@"SYNC progress: %u / %u", completed, total);
        [self showSyncStatus];
        progress.progress = (completed / (float)MAX(total, 1u));
    } else {
        [self showSyncButton];
    }
}


@end
