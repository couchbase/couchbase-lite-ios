//
//  CBLQueryEnumerator.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryEnumerator.h"
#import "CBLQueryRowsArray.h"

#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLPredicateQuery+Internal.h"
#import "CBLStatus.h"

#import "c4Document.h"
#import "c4Query.h"
#import "Fleece.h"
extern "C" {
#import "MYErrorUtils.h"
}


@implementation CBLQueryEnumerator
{
    __weak id<CBLQueryInternal> _query;
    C4Query *_c4Query;
    C4QueryEnumerator* _c4enum;
    __weak CBLQueryRow *_currentRow;
    C4Error _error;
    bool _returnDocuments;
    bool _randomAccess;
}

@synthesize c4Query=_c4Query;


- (instancetype) initWithQuery: (id<CBLQueryInternal>)query
                       c4Query: (C4Query*)c4Query
                    enumerator: (C4QueryEnumerator*)e
               returnDocuments: (bool)returnDocuments
{
    self = [super init];
    if (self) {
        if (!e)
            return nil;
        _query = query;
        _c4Query = c4Query;
        _c4enum = e;
        _returnDocuments = returnDocuments;
        CBLLog(Query, @"Beginning query enumeration (%p)", _c4enum);
    }
    return self;
}


- (void) dealloc {
    c4queryenum_free(_c4enum);
}


- (CBLDatabase*) database {
    return _query.database;
}


- (id) nextObject {
    if (_randomAccess)
        return nil;

    CBLQueryRow* current = _currentRow;
    _currentRow = nil;
    if (!_returnDocuments)
        [current stopBeingCurrent];

    id row = nil;   // row may be either a CBLQuery Row or a CBLDocument
    if (c4queryenum_next(_c4enum, &_error)) {
        row = self.currentObject;
        _currentRow = row;
    } else if (_error.code)
        CBLWarnError(Query, @"%@[%p] error: %d/%d", [self class], self, _error.domain, _error.code);
    else
        CBLLog(Query, @"End of query enumeration (%p)", _c4enum);
    return row;
}


- (id) currentObject {
    if (_returnDocuments) {
        return [_query.database documentWithID: slice2string(_c4enum->docID)];
    } else {
        Class c = _c4enum->fullTextTermCount ? [CBLFullTextQueryRow class] : [CBLQueryRow class];
        return [[c alloc] initWithEnumerator: self c4Enumerator: _c4enum];
    }
}


// Called by CBLQueryResultsArray
- (id) objectAtIndex: (NSUInteger)index {
    if (!c4queryenum_seek(_c4enum, index, &_error)) {
        NSString* message = sliceResult2string(c4error_getMessage(_error));
        [NSException raise: NSInternalInconsistencyException
                    format: @"CBLQueryEnumerator couldn't get a value: %@", message];
    }
    return self.currentObject;
}


- (NSArray*) allObjects {
    NSInteger count = (NSInteger)c4queryenum_getRowCount(_c4enum, nullptr);
    if (count >= 0) {
        _randomAccess = true;
        return [[CBLQueryRowsArray alloc] initWithEnumerator: self count: count];
    } else {
        return super.allObjects;
    }
}


//???: Should we make this public? How else can the app find the error?
- (NSError*) error {
    if (_error.code == 0)
        return nil;
    NSError* error;
    convertError(_error, &error);
    return error;
}


- (CBLQueryEnumerator*) refresh: (NSError**)outError {
    if (outError) *outError = nil;
    auto query = _query;
    if (!query)
        return nil;

    C4Error c4error;
    C4QueryEnumerator *newEnum = c4queryenum_refresh(_c4enum, &c4error);
    if (!newEnum) {
        if (c4error.code)
            convertError(c4error, outError);
        return nil;
    }
    return [[CBLQueryEnumerator alloc] initWithQuery: query
                                             c4Query: _c4Query
                                          enumerator: newEnum
                                     returnDocuments: _returnDocuments];
}


@end
