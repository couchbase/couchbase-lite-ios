//
//  CBLPredicateQuery.mm
//  Couchbase Lite
//
//  Copyright (c) 2016 Couchbase, Inc All rights reserved.
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

#import "CBLPredicateQuery.h"
#import "CBLPredicateQuery+Internal.h"

#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLQueryEnumerator.h"
#import "CBLJSON.h"
#import "CBLStatus.h"

#import "c4Document.h"
#import "c4Query.h"
#import "fleece/Fleece.h"
extern "C" {
    #import "MYErrorUtils.h"
}


@implementation CBLPredicateQuery
{
    C4Query* _c4Query;
}

@synthesize database=_db;
@synthesize where=_where, orderBy=_orderBy, groupBy=_groupBy;
@synthesize having=_having, distinct=_distinct, returning=_returning;
@synthesize offset=_offset, limit=_limit, parameters=_parameters;
#if DEBUG
@synthesize disableOffsetAndLimit=_disableOffsetAndLimit;
#endif


- (instancetype) initWithDatabase: (CBLDatabase*)db
{
    self = [super init];
    if (self) {
        _db = db;
        _orderBy = @[@"_id"];
        _limit = NSUIntegerMax;
    }
    return self;
}


- (void) dealloc {
    c4query_free(_c4Query);
}


- (void) setWhere: (id)where {
    _where = [where copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}

- (void) setOrderBy: (NSArray*)orderBy {
    _orderBy = [orderBy copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}

- (void) setGroupBy: (NSArray*)groupBy {
    _groupBy = [groupBy copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}

- (void) setHaving: (id)having {
    _having = [having copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}

- (void) setReturning: (NSArray*)returning {
    _returning = [returning copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}


- (BOOL) check: (NSError**)outError {
    NSData* jsonData = [self encodeAsJSON: outError];
    if (!jsonData)
        return NO;
    CBLLog(Query, @"Query encoded as %.*s", (int)jsonData.length, (char*)jsonData.bytes);
    C4Error c4Err;
    auto query = c4query_new(_db.c4db, {jsonData.bytes, jsonData.length}, &c4Err);
    if (!query) {
        convertError(c4Err, outError);
        return NO;
    }
    c4query_free(_c4Query);
    _c4Query = query;
    return YES;
}


- (NSString*) explain: (NSError**)outError {
    if (!_c4Query && ![self check: outError])
        return nil;
    return sliceResult2string(c4query_explain(_c4Query));
}


- (NSData*) encodeAsJSON: (NSError**)outError {
    id whereJSON = nil;
    if (_where) {
        whereJSON =  [[self class] encodePredicate: _where error: outError];
        if (!whereJSON)
            return nil;
    }

    NSMutableDictionary* q;
    if ([whereJSON isKindOfClass: [NSDictionary class]]) {
        q = [whereJSON mutableCopy];
    } else {
        q = [NSMutableDictionary new];
        if (whereJSON)
            q[@"WHERE"] = whereJSON;
    }

    if (_distinct) {
        q[@"DISTINCT"] = @YES;
    }

    if (_groupBy) {
        NSArray* group = [[self class] encodeExpressions: _groupBy
                                               aggregate: YES collation: YES
                                                   error: outError];
        if (!group)
            return nil;
        q[@"GROUP_BY"] = group;
    }

    if (_having) {
        id having =  [[self class] encodePredicate: _having error: outError];
        if (!having)
            return nil;
        q[@"HAVING"] = having;
    }

    if (_orderBy) {
        NSArray* sorts = [[self class] encodeSortDescriptors: _orderBy
                                                       error: outError];
        if (!sorts)
            return nil;
        q[@"ORDER_BY"] = sorts;
    }

    if (_returning) {
        NSArray* select = [[self class] encodeExpressions: _returning
                                                aggregate: YES collation: NO
                                                    error: outError];
        if (!select)
            return nil;
        q[@"WHAT"] = select;
    }

#if DEBUG
    if (!_disableOffsetAndLimit) {
#endif
    q[@"OFFSET"] = @[@"ifmissing()", @[@"$opt_offset"], @0];
    q[@"LIMIT"]  = @[@"ifmissing()", @[@"$opt_limit"],  @(INT64_MAX)];
#if DEBUG
    }
#endif

    return [NSJSONSerialization dataWithJSONObject: q options: 0 error: outError];
}


- (CBLQueryEnumerator*) startEnumeratorForDocs: (bool)forDocs error: (NSError**)outError {
    if (!_c4Query && ![self check: outError])
        return nullptr;

    NSDictionary* parameters = _parameters;
    if (_offset > 0 || _limit < NSUIntegerMax) {
        NSMutableDictionary* p = parameters ? [parameters mutableCopy] : [NSMutableDictionary new];
        p[@"opt_offset"] = @(_offset);
        p[@"opt_limit"]  = @(_limit);
        parameters = p;
    }
    NSData* paramJSON = nil;
    if (parameters.count > 0) {
        paramJSON = [NSJSONSerialization dataWithJSONObject: parameters
                                                    options: 0
                                                      error: outError];
        if (!paramJSON)
            return nullptr;
    }
    C4Error c4Err;
    auto e = c4query_run(_c4Query, nullptr, {paramJSON.bytes, paramJSON.length}, &c4Err);
    if (!e) {
        CBLWarnError(Query, @"CBLQuery failed: %d/%d", c4Err.domain, c4Err.code);
        convertError(c4Err, outError);
        return nullptr;
    }
    return [[CBLQueryEnumerator alloc] initWithQuery: self
                                             c4Query: _c4Query
                                          enumerator: e
                                     returnDocuments: forDocs];
}


- (NSEnumerator<CBLQueryRow*>*) run: (NSError**)outError {
    return [self startEnumeratorForDocs: false error: outError];
}


- (nullable NSEnumerator<CBLMutableDocument*>*) allDocuments: (NSError**)outError {
    return [self startEnumeratorForDocs: true error: outError];
}


@end
