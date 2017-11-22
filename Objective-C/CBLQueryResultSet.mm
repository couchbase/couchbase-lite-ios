//
//  CBLQueryResultSet.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/18/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryResultSet.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryResult.h"
#import "CBLQueryResultSet+Internal.h"
#import "CBLQueryResult+Internal.h"
#import "CBLQueryResultArray.h"
#import "CBLStatus.h"
#import "c4Query.h"
#import "CBLFleece.hh"
#import "MRoot.hh"

using namespace fleeceapi;


namespace cbl {
    // This class is responsible for holding the Fleece data in memory, while objects are using it.
    // The data happens to belong to the C4QueryEnumerator.
    class QueryResultContext : public DocContext {
    public:
        QueryResultContext(CBLDatabase *db, C4QueryEnumerator *enumerator)
        :DocContext(db, nullptr)
        ,_enumerator(enumerator)
        { }

        virtual ~QueryResultContext() {
            c4queryenum_free(_enumerator);
        }

        C4QueryEnumerator* enumerator() const   {return _enumerator;}

    private:
        C4QueryEnumerator *_enumerator;
    };
}


@implementation CBLQueryResultSet {
    __weak CBLQuery* _query;
    C4QueryEnumerator* _c4enum;
    cbl::QueryResultContext* _context;
    C4Error _error;
    bool _randomAccess;
}

@synthesize c4Query=_c4Query, columnNames=_columnNames;


- (instancetype) initWithQuery: (CBLQuery*)query
                       c4Query: (C4Query*)c4Query
                    enumerator: (C4QueryEnumerator*)e
                   columnNames: (NSDictionary*)columnNames
{
    self = [super init];
    if (self) {
        if (!e)
            return nil;
        _query = query;
        _c4Query = c4Query; // freed when query is dealloc
        _c4enum = e;
        _context = (cbl::QueryResultContext*)(new cbl::QueryResultContext(query.database, e))->retain();
        _columnNames = columnNames;
        CBLLog(Query, @"Beginning query enumeration (%p)", _c4enum);
    }
    return self;
}


- (void) dealloc {
    if (_context)
        _context->release();
}


- (CBLDatabase*) database {
    return _query.database;
}


- (id) nextObject {
    if (_randomAccess)
        return nil;
    
    id row = nil;
    if (c4queryenum_next(_c4enum, &_error)) {
        row = self.currentObject;
    } else if (_error.code)
        CBLWarnError(Query, @"%@[%p] error: %d/%d", [self class], self, _error.domain, _error.code);
    else
        CBLLog(Query, @"End of query enumeration (%p)", _c4enum);
    return row;
}


- (id) currentObject {
    return [[CBLQueryResult alloc] initWithResultSet: self
                                        c4Enumerator: _c4enum
                                             context: _context];
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
        return [[CBLQueryResultArray alloc] initWithResultSet: self count: count];
    } else
        return super.allObjects;
}


// TODO: Should we make this public? How else can the app find the error?
- (NSError*) error {
    if (_error.code == 0)
        return nil;
    NSError* error;
    convertError(_error, &error);
    return error;
}


- (CBLQueryResultSet*) refresh: (NSError**)outError {
    if (outError)
        *outError = nil;
    
    C4Error c4error;
    C4QueryEnumerator *newEnum = c4queryenum_refresh(_c4enum, &c4error);
    if (!newEnum) {
        if (c4error.code)
            convertError(c4error, outError);
        return nil;
    }
    return [[CBLQueryResultSet alloc] initWithQuery: _query
                                            c4Query: _c4Query
                                         enumerator: newEnum
                                        columnNames: _columnNames];
}


@end
