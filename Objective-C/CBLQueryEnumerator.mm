//
//  CBLQueryEnumerator.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryEnumerator.h"
#import "CBLPredicateQuery+Internal.h"
#import "CBLInternal.h"
#import "CBLCoreBridge.h"
#import "CBLStatus.h"
#import "c4Document.h"
#import "c4Query.h"
#import "Fleece.h"
extern "C" {
#import "MYErrorUtils.h"
}


@implementation CBLQueryEnumerator
{
    @protected
    id<CBLQueryInternal> _query;
    C4Query *_c4Query;
    C4QueryEnumerator* _c4enum;
    __weak CBLQueryRow *_currentRow;
    C4Error _error;
    bool _returnDocuments;
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
    CBLQueryRow* current = _currentRow;
    if (current) {
        [current stopBeingCurrent];
        _currentRow = nil;
    }

    id row = nil;   // row may be either a CBLQuery Row or a CBLDocument
    if (c4queryenum_next(_c4enum, &_error)) {
        if (_returnDocuments) {
            row = [_query.database documentWithID: slice2string(_c4enum->docID)];
        } else {
            Class c = _c4enum->fullTextTermCount ? [CBLFullTextQueryRow class] : [CBLQueryRow class];
            row = [[c alloc] initWithEnumerator: self c4Enumerator: _c4enum];
            _currentRow = row;
        }
    } else if (_error.code)
        CBLWarnError(Query, @"%@[%p] error: %d/%d", [self class], self, _error.domain, _error.code);
    else
        CBLLog(Query, @"End of query enumeration (%p)", _c4enum);
    return row;
}


//???: Should we make this public? How else can the app find the error?
- (NSError*) error {
    if (_error.code == 0)
        return nil;
    NSError* error;
    convertError(_error, &error);
    return error;
}


@end
