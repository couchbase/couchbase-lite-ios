//
//  CBLUICollectionSource.m
//
//  Based on CBLUITableSource
//  CouchbaseLite
//
//  Created by Ewan Mcdougall mrloop.com on 06/02/2013.
//  Copyright (c) 2013 Ewan Mcdougall. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#import "CBLUICollectionSource.h"
#import <CouchbaseLite/CouchbaseLite.h>


@interface CBLUICollectionSource ()
{
    UICollectionView* _collectionView;
    CBLLiveQuery* _query;
    NSMutableArray* _rows;
}
@end

@implementation CBLUICollectionSource

- (void)dealloc {
    [_query removeObserver: self forKeyPath:@"rows"];
}


#pragma mark -
#pragma mark ACCESSORS:


@synthesize collectionView=_collectionView;
@synthesize rows=_rows;


- (CBLQueryRow*) rowAtIndex: (NSUInteger)index {
    return [_rows objectAtIndex: index];
}


- (NSIndexPath*) indexPathForDocument: (CBLDocument*)document {
    NSString* documentID = document.documentID;
    NSUInteger index = 0;
    for (CBLQueryRow* row in _rows) {
        if ([row.documentID isEqualToString: documentID])
            return [NSIndexPath indexPathForRow: index inSection: 0];
        ++index;
    }
    return nil;
}


- (CBLQueryRow*) rowAtIndexPath: (NSIndexPath*)path {
    if (path.section == 0)
        return [_rows objectAtIndex: path.row];
    return nil;
}


- (CBLDocument*) documentAtIndexPath: (NSIndexPath*)path {
    return [self rowAtIndexPath: path].document;
}


#define TELL_DELEGATE(sel, obj) \
    ({id<UICollectionViewDelegate> delegate = _collectionView.delegate; \
     [delegate respondsToSelector: sel] \
        ? [delegate performSelector: sel withObject: self withObject: obj] \
        : nil;})


#pragma mark -
#pragma mark QUERY HANDLING:


- (CBLLiveQuery*) query {
    return _query;
}

- (void) setQuery:(CBLLiveQuery *)query {
    if (query != _query) {
        [_query removeObserver: self forKeyPath: @"rows"];
        _query = query;
        [_query addObserver: self forKeyPath: @"rows" options: 0 context: NULL];
        [self reloadFromQuery];
    }
}


-(void) reloadFromQuery {
    CBLQueryEnumerator* rowEnum = _query.rows;
    if (rowEnum) {
        NSArray *oldRows = _rows;
        _rows = [rowEnum.allObjects mutableCopy];
        TELL_DELEGATE(@selector(couchCollectionSource:willUpdateFromQuery:), _query);

        id delegate = _collectionView.delegate;
        SEL selector = @selector(couchCollectionSource:updateFromQuery:previousRows:);
        if ([delegate respondsToSelector: selector]) {
            [delegate couchCollectionSource: self
                            updateFromQuery: _query
                               previousRows: oldRows];
        } else {
            [self.collectionView reloadData];
        }
    }
}


- (void) observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object
                         change: (NSDictionary*)change context: (void*)context
{
    if (object == _query)
        [self reloadFromQuery];
}


#pragma mark -
#pragma mark DATA SOURCE PROTOCOL:


- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _rows.count;
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    // Allow the delegate to create its own cell:
    UICollectionViewCell* cell = TELL_DELEGATE(@selector(couchCollectionSource:cellForRowAtIndexPath:),
                                               indexPath);
    if (!cell) {
        // ...if it doesn't, create a cell for it:
        cell = [collectionView dequeueReusableCellWithReuseIdentifier: @"CBLUICollectionDelegate" forIndexPath:indexPath];
        if (!cell){
            cell = [[UICollectionViewCell alloc] init];
        }
        CBLQueryRow* row = [self rowAtIndex: indexPath.row];

        // Allow the delegate to customize the cell:
        id delegate = _collectionView.delegate;
        if ([delegate respondsToSelector: @selector(couchCollectionSource:willUseCell:forRow:)])
            [(id<CBLUICollectionDelegate>)delegate couchCollectionSource: self willUseCell: cell forRow: row];
    }
    return cell;
}


#pragma mark -
#pragma mark EDITING:


- (BOOL) deleteDocuments: (NSArray*)documents
               atIndexes: (NSArray*)indexPaths
                   error: (NSError**)outError
{
    __block NSError* error = nil;
    BOOL ok = [_query.database inTransaction: ^{
        for (CBLDocument* doc in documents) {
            if (![doc.currentRevision deleteDocument: &error])
                return NO;
        }
        return YES;
    }];
    if (!ok) {
        if (outError)
            *outError = error;
        return NO;
    }


    NSMutableIndexSet* indexSet = [NSMutableIndexSet indexSet];
    for (NSIndexPath* path in indexPaths) {
        if (path.section == 0)
            [indexSet addIndex: path.row];
    }
    [_rows removeObjectsAtIndexes: indexSet];

    [_collectionView deleteItemsAtIndexPaths: indexPaths];
    return YES;
}


- (BOOL) deleteDocumentsAtIndexes: (NSArray*)indexPaths error: (NSError**)outError {
    NSMutableArray* docs = [NSMutableArray array];
    for (NSIndexPath* path in indexPaths)
        [docs addObject: [self documentAtIndexPath: path]];
    return [self deleteDocuments: docs atIndexes: indexPaths error: outError];
}


- (BOOL) deleteDocuments: (NSArray*)documents error: (NSError**)outError {
    NSMutableArray* paths = [NSMutableArray array];
    for (CBLDocument* doc in documents)
        [paths addObject: [self indexPathForDocument: doc]];
    return [self deleteDocuments: documents atIndexes: paths error: outError];
}


#pragma mark - STATE RESTORATION:


- (NSString *) modelIdentifierForElementAtIndexPath:(NSIndexPath *)idx
                                             inView:(UIView *)view
{
    CBLQueryRow* row = [self rowAtIndexPath: idx];
    return row.key;
}


- (NSIndexPath *) indexPathForElementWithModelIdentifier:(NSString *)identifier
                                                  inView:(UIView *)view
{
    if (identifier) {
        NSUInteger i = 0;
        for (CBLQueryRow* row in _rows) {
            if ([row.key isEqual: identifier]) {
                return [NSIndexPath indexPathForItem: i inSection: 0];
            }
            ++i;
        }
    }
    return nil;
}

@end
