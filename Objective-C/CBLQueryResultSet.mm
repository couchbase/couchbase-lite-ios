//
//  CBLQueryResultSet.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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


@interface CBLQueryResultSet()
@property (atomic) BOOL isAllEnumerated;
@end


@implementation CBLQueryResultSet {
    CBLQuery* _query;
    C4QueryEnumerator* _c4enum;
    cbl::QueryResultContext* _context;
    C4Error _error;
    BOOL _isAllEnumerated;
}

@synthesize c4Query=_c4Query, columnNames=_columnNames;
@synthesize isAllEnumerated=_isAllEnumerated;


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


- (id) nextObject {
    CBL_LOCK(self.database) {
        if (_isAllEnumerated)
            return nil;
        
        id row = nil;
        if (c4queryenum_next(_c4enum, &_error)) {
            row = self.currentObject;
        } else if (_error.code) {
            CBLWarnError(Query, @"%@[%p] error: %d/%d", [self class], self, _error.domain, _error.code);
        } else {
            _isAllEnumerated = YES;
            CBLLog(Query, @"End of query enumeration (%p)", _c4enum);
        }
        return row;
    }
}


- (NSArray<CBLQueryResult*>*) allResults {
    NSMutableArray* results = [NSMutableArray array];
    CBLQueryResult* r;
    while((r = [self nextObject])) {
        [results addObject: r];
    }
    return results;
    // return [self allObjects];
}


#pragma mark - Internal


- (CBLDatabase*) database {
    return _query.database;
}



- (id) currentObject {
    return [[CBLQueryResult alloc] initWithResultSet: self
                                        c4Enumerator: _c4enum
                                             context: _context];
}

// Called by CBLQueryResultsArray
- (id) objectAtIndex: (NSUInteger)index {
    // TODO: We should make it strong reference instead:
    // https://github.com/couchbase/couchbase-lite-ios/issues/1983
    CBLDatabase* db = self.database;
    CBL_LOCK(db) {
        if (!c4queryenum_seek(_c4enum, index, &_error)) {
            NSString* message = sliceResult2string(c4error_getMessage(_error));
            [NSException raise: NSInternalInconsistencyException
                        format: @"CBLQueryEnumerator couldn't get a value: %@", message];
        }
        return self.currentObject;
    }
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
    C4QueryEnumerator *newEnum;
    
    CBLDatabase* db = self.database;
    CBL_LOCK(db) {
        newEnum = c4queryenum_refresh(_c4enum, &c4error);
    }
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
