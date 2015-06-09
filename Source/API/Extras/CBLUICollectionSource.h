//
//  CBLUICollectionSource.h
//
//  Based on CBLUITableSource
//  CouchbaseLite
//
//  Created by Ewan Mcdougall mrloop.com on 06/02/2013.
//  Copyright (c) 2013 Ewan Mcdougall. All rights reserved.
//
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLBase.h"
#import <UIKit/UIKit.h>
@class CBLDocument, CBLLiveQuery, CBLQueryRow, RESTOperation;

NS_ASSUME_NONNULL_BEGIN

/** A UICollectionView data source driven by a CBLLiveQuery.
    It populates the collection view from the query rows, and automatically updates the collection
    as the query results change when the database is updated.
    A CBLUICollectionSource can be created in a nib. If so, its collectionView outlet should be
    wired up to the UICollectionView it manages, and the collection view's dataSource outlet should
    be wired to it. */
@interface CBLUICollectionSource : NSObject <UICollectionViewDataSource
#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000)
                                                                     , UIDataSourceModelAssociation
#endif
>
@property (nonatomic, retain) IBOutlet UICollectionView* collectionView;

@property (retain) CBLLiveQuery* query;

/** Rebuilds the collection from the query's current .rows property. */
-(void) reloadFromQuery;

#pragma mark Row Accessors:

/** The current array of CBLQueryRows being used as the data source for the collection. */
@property (nonatomic, readonly, nullable) NSMutableArray* rows;

/** Convenience accessor to get the row object for a given collection row index. */
- (nullable CBLQueryRow*) rowAtIndex: (NSUInteger)index;

/** Convenience accessor to find the index path of the row with a given document. */
- (nullable NSIndexPath*) indexPathForDocument: (CBLDocument*)document;

/** Convenience accessor to return the query row at a given index path. */
- (nullable CBLQueryRow*) rowAtIndexPath: (NSIndexPath*)path;

/** Convenience accessor to return the document at a given index path. */
- (nullable CBLDocument*) documentAtIndexPath: (NSIndexPath*)path;



#pragma mark Editing The Collection:

/** Deletes the documents at the given row indexes, animating the removal from the collection. */
- (BOOL) deleteDocumentsAtIndexes: (CBLArrayOf(NSIndexPath*)*)indexPaths
                            error: (NSError**)outError;

/** Deletes the given documents, animating the removal from the collection. */
- (BOOL) deleteDocuments: (CBLArrayOf(CBLDocument*)*)documents
                   error: (NSError**)outError;

@end

#pragma mark CouchUICollectionDelegate:

/** Additional methods for the collection view's delegate, that will be invoked by the CouchUICollectionSource. */
@protocol CBLUICollectionDelegate <UICollectionViewDelegate>
@optional

/** Allows delegate to return its own custom cell, just like -collectionView:cellForRowAtIndexPath:.
     If this returns nil the collection source will create its own cell, as if this method were not implemented. */
- (UICollectionViewCell *)couchCollectionSource:(CBLUICollectionSource*)source
                          cellForRowAtIndexPath:(NSIndexPath *)indexPath;

/** Called after the query's results change, before the collection view is reloaded. */
- (void)couchCollectionSource:(CBLUICollectionSource*)source
          willUpdateFromQuery:(CBLLiveQuery*)query;

/** Called after the query's results change to update the collection view. If this method is not implemented by the delegate, reloadData is called on the collection view.*/
- (void)couchCollectionSource:(CBLUICollectionSource*)source
              updateFromQuery:(CBLLiveQuery*)query
                 previousRows:(CBLArrayOf(CBLQueryRow*) *)previousRows;

/** Called from -collectionView:cellForItemAtIndexPath: just before it returns, giving the delegate a chance to customize the new cell. */
- (void)couchCollectionSource:(CBLUICollectionSource*)source
                  willUseCell:(UICollectionViewCell*)cell
                       forRow:(CBLQueryRow*)row;

@end


NS_ASSUME_NONNULL_END
