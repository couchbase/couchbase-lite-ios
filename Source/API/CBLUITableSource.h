//
//  CBLUITableSource.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/2/11.
//  Copyright 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
@class CBLDocument, CBLLiveQuery, CBLQueryRow;

/** A UITableView data source driven by a CBLLiveQuery.
    It populates the table rows from the query rows, and automatically updates the table as the
    query results change when the database is updated.
    A CBLUITableSource can be created in a nib. If so, its tableView outlet should be wired up to
    the UITableView it manages, and the table view's dataSource outlet should be wired to it. */
@interface CBLUITableSource : NSObject <UITableViewDataSource
#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000)
                                                            , UIDataSourceModelAssociation
#endif
                                                                                          >
/** The table view to manage. */
@property (nonatomic, retain) IBOutlet UITableView* tableView;

/** The query whose rows will be displayed in the table. */
@property (retain) CBLLiveQuery* query;

/** Rebuilds the table from the query's current .rows property. */
-(void) reloadFromQuery;


#pragma mark Row Accessors:

/** The current array of CBLQueryRows being used as the data source for the table. */
@property (nonatomic, readonly) NSArray* rows;

/** Convenience accessor to get the row object for a given table row index. */
- (CBLQueryRow*) rowAtIndex: (NSUInteger)index;

/** Convenience accessor to find the index path of the row with a given document. */
- (NSIndexPath*) indexPathForDocument: (CBLDocument*)document           __attribute__((nonnull));

/** Convenience accessor to return the query row at a given index path. */
- (CBLQueryRow*) rowAtIndexPath: (NSIndexPath*)path                     __attribute__((nonnull));

/** Convenience accessor to return the document at a given index path. */
- (CBLDocument*) documentAtIndexPath: (NSIndexPath*)path                __attribute__((nonnull));


#pragma mark Displaying The Table:

/** If non-nil, specifies the property name of the query row's value that will be used for the table row's visible label.
    If the row's value is not a dictionary, or if the property doesn't exist, the property will next be looked up in the document's properties.
    If this doesn't meet your needs for labeling rows, you should implement -couchTableSource:willUseCell:forRow: in the table's delegate. */
@property (copy) NSString* labelProperty;


#pragma mark Editing The Table:

/** Is the user allowed to delete rows by UI gestures? (Defaults to YES.) */
@property (nonatomic) BOOL deletionAllowed;

/** Deletes the documents at the given row indexes, animating the removal from the table. */
- (BOOL) deleteDocumentsAtIndexes: (NSArray*)indexPaths
                            error: (NSError**)outError                  __attribute__((nonnull(1)));

/** Asynchronously deletes the given documents, animating the removal from the table. */
- (BOOL) deleteDocuments: (NSArray*)documents
                   error: (NSError**)outError                           __attribute__((nonnull(1)));

@end


/** Additional methods for the table view's delegate, that will be invoked by the CBLUITableSource. */
@protocol CBLUITableDelegate <UITableViewDelegate>
@optional

/** Allows delegate to return its own custom cell, just like -tableView:cellForRowAtIndexPath:.
    If this returns nil the table source will create its own cell, as if this method were not implemented. */
- (UITableViewCell *)couchTableSource:(CBLUITableSource*)source
                cellForRowAtIndexPath:(NSIndexPath *)indexPath;

/** Called after the query's results change, before the table view is reloaded. */
- (void)couchTableSource:(CBLUITableSource*)source
     willUpdateFromQuery:(CBLLiveQuery*)query;

/** Called after the query's results change to update the table view. If this method is not implemented by the delegate, reloadData is called on the table view.*/
- (void)couchTableSource:(CBLUITableSource*)source
         updateFromQuery:(CBLLiveQuery*)query
            previousRows:(NSArray *)previousRows;

/** Called from -tableView:cellForRowAtIndexPath: just before it returns, giving the delegate a chance to customize the new cell. */
- (void)couchTableSource:(CBLUITableSource*)source
             willUseCell:(UITableViewCell*)cell
                  forRow:(CBLQueryRow*)row;

/** Called when the user wants to delete a row.
    If the delegate implements this method, it will be called *instead of* the
    default behavior of deleting the associated document.
    @param source  The CBLUITableSource
    @param row  The query row corresponding to the row to delete
    @return  True if the row was deleted, false if not. */
- (bool)couchTableSource:(CBLUITableSource*)source
               deleteRow:(CBLQueryRow*)row;

/** Called upon failure of a document deletion triggered by the user deleting a row. */
- (void)couchTableSource:(CBLUITableSource*)source
            deleteFailed:(NSError*)error;

@end
