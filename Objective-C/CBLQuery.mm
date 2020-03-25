//
//  CBLQuery.mm
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

#import "CBLQuery.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLLiveQuery.h"
#import "CBLPropertyExpression.h"
#import "CBLQuery+Internal.h"
#import "CBLQuery+JSON.h"
#import "CBLQueryExpression+Internal.h"
#import "CBLQueryResultSet+Internal.h"
#import "CBLStatus.h"
#import "c4Query.h"
#import "fleece/slice.hh"

using namespace fleece;

@implementation CBLQuery
{
    NSData* _json;
    C4Query* _c4Query;
    NSDictionary* _columnNames;
    CBLLiveQuery* _liveQuery;
    
    CBLQueryDataSource* _from;
}

@synthesize database=_database;
@synthesize JSONRepresentation=_json;
@synthesize parameters=_parameters;

- (instancetype) initWithDatabase: (CBLDatabase*)database
               JSONRepresentation: (NSData*)json
{
    Assert(database);
    Assert(json);
    self = [super init];
    if (self) {
        _database = database;
        _json = json;
    }
    return self;
}

- (instancetype) initWithSelect: (NSArray<CBLQuerySelectResult*>*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)_join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit;
{
    // Encode the query to JSON:
    NSData* json;
    @autoreleasepool {
        NSMutableDictionary *root = [NSMutableDictionary dictionary];

        // DISTINCT:
        if (distinct)
            root[@"DISTINCT"] = @(YES);

        // JOIN / FROM:
        _from = from;
        NSMutableArray* fromArray;
        NSDictionary* as = [from asJSON];
        if (as.count > 0) {
            if (!fromArray)
                fromArray = [NSMutableArray array];
            [fromArray addObject: as];
        } if (_join) {
            if (!fromArray)
                fromArray = [NSMutableArray array];
            for (CBLQueryJoin* join in _join) {
                [fromArray addObject: [join asJSON]];
            }
        }
        if (fromArray.count > 0)
            root[@"FROM"] = fromArray;

        // SELECT:
        NSMutableArray* selects = [NSMutableArray array];
        for (CBLQuerySelectResult* selected in select) {
            [selects addObject: [selected asJSON]];
        }
        if (selects.count == 0) // Empty selects means SELECT *
            [selects addObject: [[CBLQuerySelectResult allFrom: as[@"AS"]] asJSON]];
        root[@"WHAT"] = selects;

        // WHERE:
        if (where)
            root[@"WHERE"] = [where asJSON];

        // GROUPBY:
        if (groupBy) {
            NSMutableArray* groupByArray = [NSMutableArray array];
            for (CBLQueryExpression* expr in groupBy) {
                [groupByArray addObject: [expr asJSON]];
            }
            root[@"GROUP_BY"] = groupByArray;
        }

        // HAVING:
        if (having)
            root[@"HAVING"] = [having asJSON];

        // ORDERBY:
        if (orderings) {
            NSMutableArray* orderBy = [NSMutableArray array];
            for (CBLQueryOrdering* o in orderings) {
                [orderBy addObject: [o asJSON]];
            }
            root[@"ORDER_BY"] = orderBy;
        }

        // LIMIT/OFFSET:
        if (limit) {
            NSArray* limitObj = [limit asJSON];
            root[@"LIMIT"] = limitObj[0];
            if (limitObj.count > 1)
                root[@"OFFSET"] = limitObj[1];
        }
        
        NSError* error;
        json = [NSJSONSerialization dataWithJSONObject: root options: 0 error: &error];
        Assert(json, @"Failed to encode query as JSON: %@", error);
    }
    return [self initWithDatabase: (CBLDatabase*)from.source JSONRepresentation: json];
}

- (void) dealloc {
    [_liveQuery stop];
    
    CBL_LOCK(self.database) {
        c4query_release(_c4Query);
    }
}

- (NSString*) description {
    NSString* desc = [[NSString alloc] initWithData: _json encoding: NSUTF8StringEncoding];
    return [NSString stringWithFormat: @"%@[json=%@]", self.class, desc];
}

#pragma mark - Parameters

- (CBLQueryParameters*) parameters {
    CBL_LOCK(self) {
        return _parameters;
    }
}

- (void) setParameters: (CBLQueryParameters*)parameters {
    CBL_LOCK(self) {
        if (parameters)
            _parameters = [[CBLQueryParameters alloc] initWithParameters: parameters readonly: YES];
        else
            _parameters = nil;
        [_liveQuery queryParametersChanged];
    }
}

- (NSString*) explain: (NSError**)outError {
    if (![self check: outError])
        return nil;
    
    CBL_LOCK(self.database) {
        return sliceResult2string(c4query_explain(_c4Query));
    }
}

- (nullable CBLQueryResultSet*) execute: (NSError**)outError {
    if (![self check: outError])
        return nil;
    
    C4QueryOptions options = kC4DefaultQueryOptions;
    
    NSData* params = nil;
    CBL_LOCK(self) {
        params = [_parameters encode: outError];
        if (_parameters && !params)
            return nil;
    }
    
    C4Error c4Err;
    C4QueryEnumerator* e;
    CBL_LOCK(self.database) {
        e = c4query_run(_c4Query, &options, {params.bytes, params.length}, &c4Err);
    }
    if (!e) {
        CBLWarnError(Query, @"CBLQuery failed: %d/%d", c4Err.domain, c4Err.code);
        convertError(c4Err, outError);
        return nullptr;
    }
    
    return [[CBLQueryResultSet alloc] initWithQuery: self
                                            c4Query: _c4Query
                                         enumerator: e
                                        columnNames: _columnNames];
}

- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLQueryChange*))listener {
    return [self addChangeListenerWithQueue: nil listener: listener];
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLQueryChange*))listener
{
    CBLAssertNotNil(listener);
    
    CBL_LOCK(self) {
        if (!_liveQuery)
            _liveQuery = [[CBLLiveQuery alloc] initWithQuery: self];
        return [_liveQuery addChangeListenerWithQueue: queue listener: listener]; // Auto-start
    }
}

- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBLAssertNotNil(token);
    
    CBL_LOCK(self) {
        [_liveQuery removeChangeListenerWithToken: token];
    }
}

#pragma mark - Internal

- (instancetype) copyWithZone: (NSZone*)zone {
    CBL_LOCK(self) {
        CBLQuery* q =  [[[self class] alloc] initWithDatabase: _database JSONRepresentation: _json];
        q.parameters = _parameters;
        return q;
    }
}

#pragma mark - Private

- (BOOL) check: (NSError**)outError {
    CBL_LOCK(self) {
        if (_c4Query)
            return YES;
        
        [self.database mustBeOpenLocked];
        
        // Compile JSON query:
        C4Error c4Err;
        C4Query* query;
        CBL_LOCK(self.database) {
            query = c4query_new(self.database.c4db, {_json.bytes, _json.length}, &c4Err);
        }
        
        if (!query) {
            convertError(c4Err, outError);
            return NO;
        }
        
        Assert(!_c4Query);
        _c4Query = query;

        // Generate column name dictionary:
        NSMutableDictionary* cols = [NSMutableDictionary dictionary];
        unsigned n = c4query_columnCount(_c4Query);
        for (unsigned i = 0; i < n; ++i) {
            slice title = c4query_columnTitle(_c4Query, i);
            NSString* titleString = slice2string(title);
            if ([titleString hasPrefix: @"*"]) {
                titleString = _from.columnName;
            }
            cols[titleString] = @(i);
        }
        _columnNames = [cols copy];
        
        return YES;
    }
}

@end
