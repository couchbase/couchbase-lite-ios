//
//  CBLUITableSource.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/2/11.
//  Copyright 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLUITableSource.h"
#import "CouchbaseLite.h"


@interface CBLUITableSource ()
{
    @private
    UITableView* _tableView;
    CBLLiveQuery* _query;
	NSMutableArray* _rows;
    NSString* _labelProperty;
    BOOL _deletionAllowed;
}
@end


@implementation CBLUITableSource


- (instancetype) init {
    self = [super init];
    if (self) {
        _deletionAllowed = YES;
    }
    return self;
}


- (void)dealloc {
    [_query removeObserver: self forKeyPath: @"rows"];
}


#pragma mark -
#pragma mark ACCESSORS:


@synthesize tableView=_tableView;
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
    (([_tableView.delegate respondsToSelector: sel]) \
        ? [_tableView.delegate performSelector: sel withObject: self withObject: obj] \
        : nil)


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
        TELL_DELEGATE(@selector(couchTableSource:willUpdateFromQuery:), _query);
        
        id delegate = _tableView.delegate;
        SEL selector = @selector(couchTableSource:updateFromQuery:previousRows:);
        if ([delegate respondsToSelector: selector]) {
            [delegate couchTableSource: self 
                       updateFromQuery: _query
                          previousRows: oldRows];
        } else {
            [self.tableView reloadData];
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


@synthesize labelProperty=_labelProperty;


- (NSString*) labelForRow: (CBLQueryRow*)row {
    id value = row.value;
    if (_labelProperty) {
        if ([value isKindOfClass: [NSDictionary class]])
            value = [value objectForKey: _labelProperty];
        else
            value = nil;
        if (!value)
            value = [row.document propertyForKey: _labelProperty];
    }
    return [value description];
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Allow the delegate to create its own cell:
    UITableViewCell* cell = TELL_DELEGATE(@selector(couchTableSource:cellForRowAtIndexPath:),
                                          indexPath);
    if (!cell) {
        // ...if it doesn't, create a cell for it:
        cell = [tableView dequeueReusableCellWithIdentifier: @"CBLUITableDelegate"];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle: UITableViewCellStyleDefault
                                          reuseIdentifier: @"CBLUITableDelegate"];
        
        CBLQueryRow* row = [self rowAtIndex: indexPath.row];
        cell.textLabel.text = [self labelForRow: row];
        
        // Allow the delegate to customize the cell:
        id delegate = _tableView.delegate;
        if ([delegate respondsToSelector: @selector(couchTableSource:willUseCell:forRow:)])
            [(id<CBLUITableDelegate>)delegate couchTableSource: self willUseCell: cell forRow: row];
    }
    return cell;
}


#pragma mark -
#pragma mark EDITING:


@synthesize deletionAllowed=_deletionAllowed;


- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return _deletionAllowed;
}


- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Queries have a sort order so reordering doesn't generally make sense.
    return NO;
}


- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle 
         forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the document from the database.

        CBLQueryRow* row = [self rowAtIndex: indexPath.row];
        id<CBLUITableDelegate> delegate = (id<CBLUITableDelegate>)_tableView.delegate;
        if ([delegate respondsToSelector: @selector(couchTableSource:deleteRow:)]) {
            if (![delegate couchTableSource: self deleteRow: row])
                return;
        } else {
            NSError* error;
            if (![row.document.currentRevision deleteDocument: &error]) {
                TELL_DELEGATE(@selector(couchTableSource:deleteFailed:), error);
                return;
            }
        }

        // Delete the row from the table data source.
        [_rows removeObjectAtIndex: indexPath.row];
        [self.tableView deleteRowsAtIndexPaths: [NSArray arrayWithObject:indexPath]
                              withRowAnimation: UITableViewRowAnimationFade];
    }
}


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

    [_tableView deleteRowsAtIndexPaths: indexPaths withRowAnimation: UITableViewRowAnimationFade];
    return YES;
}


- (BOOL) deleteDocumentsAtIndexes: (NSArray*)indexPaths error: (NSError**)outError {
    NSMutableArray* documents = [[NSMutableArray alloc] initWithCapacity: indexPaths.count];
    for (NSIndexPath* path in indexPaths)
        [documents addObject: [self documentAtIndexPath: path]];
    return [self deleteDocuments: documents atIndexes: indexPaths error: outError];
}


- (BOOL) deleteDocuments: (NSArray*)documents error: (NSError**)outError {
    NSMutableArray* indexPaths = [[NSMutableArray alloc] initWithCapacity: documents.count];
    for (CBLDocument* doc in documents)
        [indexPaths addObject: [self indexPathForDocument: doc]];
    return [self deleteDocuments: documents atIndexes: indexPaths error: outError];
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
