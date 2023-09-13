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

using namespace fleece;

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
            [database() safeBlock:^{
                c4queryenum_release(_enumerator);
            }];
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

@synthesize columnNames=_columnNames;
@synthesize isAllEnumerated=_isAllEnumerated;

- (instancetype) initWithQuery: (CBLQuery*)query
                    enumerator: (C4QueryEnumerator*)e
                   columnNames: (NSDictionary*)columnNames
{
    self = [super init];
    if (self) {
        if (!e)
            return nil;
        _query = query;
        _c4enum = e;
        _context = (cbl::QueryResultContext*)(new cbl::QueryResultContext(query.database, e))->retain();
        _columnNames = columnNames;
        CBLLogInfo(Query, @"Beginning query enumeration (%p)", _c4enum);
    }
    return self;
}

- (void) dealloc {
    if (_context)
        _context->release();
}

- (id) nextObject {
    __block id row = nil;
    [self.database safeBlock: ^{
        if (self->_isAllEnumerated)
            return;
        
        if (c4queryenum_next(self->_c4enum, &self->_error)) {
            row = self.currentObject;
        } else if (self->_error.code) {
            CBLWarnError(Query, @"%@[%p] error: %d/%d", [self class], self, self->_error.domain, self->_error.code);
        } else {
            self->_isAllEnumerated = YES;
            CBLLogInfo(Query, @"End of query enumeration (%p)", self->_c4enum);
        }
    }];
    return row;
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

- (CBLQuery*) query {
    return  _query;
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
    
    __block id result;
    [db safeBlock: ^{
        if (!c4queryenum_seek(self->_c4enum, index, &self->_error)) {
            NSString* message = sliceResult2string(c4error_getMessage(self->_error));
            [NSException raise: NSInternalInconsistencyException
                        format: @"CBLQueryEnumerator couldn't get a value: %@", message];
        }
        result = self.currentObject;
    }];
    return result;
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
    
    __block C4Error c4error;
    __block C4QueryEnumerator *newEnum;
    
    CBLDatabase* db = self.database;
    [db safeBlock: ^{
        newEnum = c4queryenum_refresh(self->_c4enum, &c4error);
    }];
    if (!newEnum) {
        if (c4error.code)
            convertError(c4error, outError);
        return nil;
    }
    return [[CBLQueryResultSet alloc] initWithQuery: _query
                                         enumerator: newEnum
                                        columnNames: _columnNames];
}

@end
