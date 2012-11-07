//
//  CouchUITableSource.h
//  TouchDB
//
//  Created by Jens Alfke on 8/2/11.
//  Copyright 2011 Couchbase, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
@class TDDocument, TDLiveQuery, TDQueryRow, RESTOperation;

/** A UITableView data source driven by a TDLiveQuery. */
@interface TDUITableSource : NSObject <UITableViewDataSource>

@property (nonatomic, retain) IBOutlet UITableView* tableView;

@property (retain) TDLiveQuery* query;

/** Rebuilds the table from the query's current .rows property. */
-(void) reloadFromQuery;


#pragma mark Row Accessors:

/** The current array of TDQueryRows being used as the data source for the table. */
@property (nonatomic, readonly) NSArray* rows;

/** Convenience accessor to get the row object for a given table row index. */
- (TDQueryRow*) rowAtIndex: (NSUInteger)index;

/** Convenience accessor to find the index path of the row with a given document. */
- (NSIndexPath*) indexPathForDocument: (TDDocument*)document;

/** Convenience accessor to return the document at a given index path. */
- (TDDocument*) documentAtIndexPath: (NSIndexPath*)path;


#pragma mark Displaying The Table:

/** If non-nil, specifies the property name of the query row's value that will be used for the table row's visible label.
    If the row's value is not a dictionary, or if the property doesn't exist, the property will next be looked up in the document's properties.
    If this doesn't meet your needs for labeling rows, you should implement -couchTableSource:willUseCell:forRow: in the table's delegate. */
@property (copy) NSString* labelProperty;


#pragma mark Editing The Table:

/** Is the user allowed to delete rows by UI gestures? (Defaults to YES.) */
@property (nonatomic) BOOL deletionAllowed;

/** Asynchronously deletes the documents at the given row indexes, animating the removal from the table. */
- (void) deleteDocumentsAtIndexes: (NSArray*)indexPaths;

/** Asynchronously deletes the given documents, animating the removal from the table. */
- (void) deleteDocuments: (NSArray*)documents;

@end


/** Additional methods for the table view's delegate, that will be invoked by the TDUITableSource. */
@protocol TouchUITableDelegate <UITableViewDelegate>
@optional

/** Allows delegate to return its own custom cell, just like -tableView:cellForRowAtIndexPath:.
    If this returns nil the table source will create its own cell, as if this method were not implemented. */
- (UITableViewCell *)couchTableSource:(TDUITableSource*)source
                cellForRowAtIndexPath:(NSIndexPath *)indexPath;

/** Called after the query's results change, before the table view is reloaded. */
- (void)couchTableSource:(TDUITableSource*)source
     willUpdateFromQuery:(TDLiveQuery*)query;

/** Called after the query's results change to update the table view. If this method is not implemented by the delegate, reloadData is called on the table view.*/
- (void)couchTableSource:(TDUITableSource*)source
         updateFromQuery:(TDLiveQuery*)query
            previousRows:(NSArray *)previousRows;

/** Called from -tableView:cellForRowAtIndexPath: just before it returns, giving the delegate a chance to customize the new cell. */
- (void)couchTableSource:(TDUITableSource*)source
             willUseCell:(UITableViewCell*)cell
                  forRow:(TDQueryRow*)row;

/** Called if a TDDB operation invoked by the source (e.g. deleting a document) fails. */
- (void)couchTableSource:(TDUITableSource*)source
         operationFailed:(RESTOperation*)op;

@end