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
#import "CBLQuery+N1QL.h"
#import "CBLQueryExpression+Internal.h"
#import "CBLQueryResultSet+Internal.h"
#import "CBLStatus.h"
#import "c4Query.h"
#import "fleece/slice.hh"
#import "CBLStringBytes.h"

using namespace fleece;

@implementation CBLQuery
{
    NSData* _json;
    NSString* _expressions;
    C4QueryLanguage _language;
    C4Query* _c4Query;
    NSDictionary* _columnNames;
    CBLLiveQuery* _liveQuery;
    
    CBLQueryDataSource* _from;
}

@synthesize database=_database;
@synthesize JSONRepresentation=_json;
@synthesize parameters=_parameters;
@synthesize expressions=_expressions;

#pragma mark - JSON representation

#define SPLAT(S)    (int)(S).size, (char *)(S).buf

- (instancetype) initWithDatabase: (CBLDatabase*)database
               JSONRepresentation: (NSData*)json
{
    Assert(database);
    Assert(json);
    self = [super init];
    if (self) {
        _database = database;
        _json = json;
        _language = kC4JSONQuery;
    }
    return self;
}

- (nullable instancetype) initWithDatabase: (CBLDatabase*)database
                               expressions: (NSString*)expressions
                                     error: (NSError**)error
{
    Assert(database);
    Assert(expressions);
    self = [super init];
    if (self) {
        _database = database;
        _expressions = expressions;
        _language = kC4N1QLQuery;
        
        // Return error if the N1QL query expression is not compiled:
        if (![self compile: error])
            return nil;
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
        bool cbl_3715 = false;
        // DISTINCT:
        if (distinct)
            root[@"DISTINCT"] = @(YES);

        // JOIN / FROM:
        _from = from;
        NSMutableArray* fromArray;
        NSDictionary* as = [from asJSON];

        if ([as[@"AS"] isEqualToString: @"cbl-3715"]) {
            cbl_3715 = true;
        }
        
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
        
        if (cbl_3715) {
#if 0
            // const char* c_str = R"--({"FROM":[{"COLLECTION":"_default"}],"WHAT":[["_.",["meta()"],".id"]],"WHERE":[">",["_.",["meta()"],".expiration"],1667952670887.845]})--";
            NSString* ns_str = [NSString stringWithUTF8String:
                                R"--({"FROM":[{"COLLECTION":"_default"}],"WHAT":[["_.",["meta()"],".id"]],)--"
                                R"--("WHERE":[">",["_.",["meta()"],".expiration"],1667952670887.845]})--"];

            NSString* orig = [[NSString alloc] initWithData: json encoding:NSUTF8StringEncoding];
            NSMutableArray *wh = (NSMutableArray*)root[@"WHERE"];
            NSString* s = @"{\"FROM\":[{\"COLLECTION\":\"_default\"}],\"WHAT\":[[\"_.\",[\"meta()\"],\".id\"]],\"WHERE\":[\">\",[\"_.\",[\"meta()\"],\".expiration\"],";
            s = [s stringByAppendingFormat:@"%f]}", [wh[2] doubleValue]];
            NSLog(@"s         = %@\n", s);
            NSLog(@"ns_str    = %@\n", ns_str);
            NSLog(@"orig json = %@\n", orig);
#else
//            NSString* s = [NSString stringWithUTF8String:
//                                R"--({"FROM":[{"COLLECTION":"_default"}],"WHAT":[["_.",["meta()"],".expiration"]],)--"
//                                R"--("WHERE":[">",1667952670887.845,1.1]})--"];
//            NSString* s = [NSString stringWithUTF8String:
//                                R"--({"FROM":[{"COLLECTION":"_default"}],"WHAT":[["_.",["meta()"],".expiration"]],)--"
//                                R"--("WHERE":["toboolean()",[">",1.6,1.2]]})--"];
//

            const char* const q = "{"
                R"--("FROM":[{"COLLECTION":"_default"}],"WHAT":[)--"
                R"--(["toboolean()",[">",1.6,1.2]])--"
//                R"--(["or",["toboolean()",[">",1.6,1.2]],["toboolean()",["<",1.6,1.2]]])--"
                R"--(,["or",["toboolean()",[">",1.6,1.2]],"false"])--"
                R"--(,["and",["toboolean()",[">",1.6,1.2]],"true"])--"
                R"--(,["toboolean()",["<",1.6,1.2]])--"
                R"--(,["or",["toboolean()",[">",1.6,1.2]],["toboolean()",["<",1.6,1.2]]])--"
                R"--(,["toboolean()",["<",1.2,1.6]],["toboolean()",["=",1.2,1.2]])--"
                R"--(,["toboolean()",[">",2,1]],["+",1.6,1.2])--"
                     "]"
                     "}";
            NSString* s = [NSString stringWithUTF8String:q];
//            NSString* s = [NSString stringWithUTF8String:
//                R"--({"FROM":[{"COLLECTION":"_default"}],"WHAT":[["_.",["meta()"],".id"]],"WHERE":["toboolean()",[">",1.6,1.2]]})--"];

//            NSString* s = [NSString stringWithUTF8String:
//                           R"--({"FROM":[{"COLLECTION":"_default"}],"WHAT":[["_.",["meta()"],".expiration"]]})--"];
            
#endif
            json = [s dataUsingEncoding: NSUTF8StringEncoding];
        }
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
    if (_language == kC4JSONQuery) {
        NSString* desc = [[NSString alloc] initWithData: _json encoding: NSUTF8StringEncoding];
        return [NSString stringWithFormat: @"%@[json=%@]", self.class, desc];
    } else {
        return [NSString stringWithFormat: @"%@[n1ql=%@]", self.class, _expressions];
    }
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
    if (![self compile: outError])
        return nil;
    
    CBL_LOCK(self.database) {
        return sliceResult2string(c4query_explain(_c4Query));
    }
}

- (nullable CBLQueryResultSet*) execute: (NSError**)outError {
    if (![self compile: outError])
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

- (NSUInteger) columnCount {
    CBL_LOCK(self) {
        return c4query_columnCount(_c4Query);
    }
}

#pragma mark - Private

- (BOOL) compile: (NSError**)outError {
    CBL_LOCK(self) {
        if (_c4Query)
            return YES;
        
        [self.database mustBeOpenLocked];
        
        // Compile JSON query:
        C4Error c4Err;
        C4Query* query;
        CBL_LOCK(self.database) {
            if (_language == kC4JSONQuery) {
                assert(_json);
                slice json_sl {_json.bytes, _json.length};
                if (json_sl.containsBytes("COLLECTION"_sl)) {
                    NSString* json = [[NSString alloc] initWithData:_json encoding:NSUTF8StringEncoding];
                    NSLog(@"CBLQuery compile JSON %@\n", json);
                }
                query = c4query_new2(self.database.c4db,
                                     kC4JSONQuery, {_json.bytes, _json.length}, nullptr, &c4Err);
            } else {
                assert(_expressions);
                CBLStringBytes exp(_expressions);
                query = c4query_new2(self.database.c4db, kC4N1QLQuery, exp, nullptr, &c4Err);
            }
        }
        
        if (!query) {
            convertError(c4Err, outError);
            return NO;
        }
        
        C4StringResult expln = c4query_explain(query);
        slice json_sl {expln};
        std::string explns {json_sl};
        auto nn = explns.rfind("\n\n");
        json_sl.moveStart(nn + 2);
        json_sl.shorten(json_sl.size - 1);
        CBLLogInfo(Query, @"CBLQuery JSON: %.*s\n", SPLAT(json_sl));

        Assert(!_c4Query);
        _c4Query = query;

        // Generate column name dictionary:
        NSMutableDictionary* cols = [NSMutableDictionary dictionary];
        unsigned n = c4query_columnCount(_c4Query);
        for (unsigned i = 0; i < n; ++i) {
            slice title = c4query_columnTitle(_c4Query, i);
            NSString* titleString = slice2string(title);
            cols[titleString] = @(i);
        }
        _columnNames = [cols copy];
        
        return YES;
    }
}

@end
