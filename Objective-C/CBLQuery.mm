//
//  CBLQuery.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLQueryEnumerator.h"
#import "CBLCoreBridge.h"
#import "CBLInternal.h"
#import "CBLLiveQuery+Internal.h"
#import "CBLPredicateQuery+Internal.h"
#import "CBLQuery+Internal.h"
#import "CBLStatus.h"
#import "c4Query.h"


@implementation CBLQuery
{
    C4Query* _c4Query;
}

@synthesize database=_database;
@synthesize select=_select, from=_from, where=_where, orderBy=_orderBy, distinct=_distinct;


- (instancetype) initWithSelect: (CBLQuerySelect*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                          where: (CBLQueryExpression*)where
                        orderBy: (CBLQueryOrderBy*)orderBy
{
    self = [super init];
    if (self) {
        _from = from;
        _distinct = distinct;
        _select = select;
        _where = where;
        _orderBy = orderBy;
    }
    return self;
}


- (void) dealloc {
    c4query_free(_c4Query);
}


#pragma mark - SELECT > FROM


+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
{
    return [[[self class] alloc] initWithSelect: select
                                       distinct: NO
                                           from: from
                                          where: nil
                                        orderBy: nil];
}


+ (instancetype) selectDistinct: (CBLQuerySelect*)select
                           from: (CBLQueryDataSource*)from
{
    return [[[self class] alloc] initWithSelect: select distinct: YES
                                           from: from
                                          where: nil
                                        orderBy: nil];
}


#pragma mark - SELECT > FROM > WHERE


+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (CBLQueryExpression*)where
{
    return [[[self class] alloc] initWithSelect: select
                                       distinct: NO
                                           from: from
                                          where: where
                                        orderBy: nil];
}


+ (instancetype) selectDistinct: (CBLQuerySelect*)select
                           from: (CBLQueryDataSource*)from
                          where: (CBLQueryExpression*)where
{
    return [[[self class] alloc] initWithSelect: select
                                       distinct: YES
                                           from: from
                                          where: where
                                        orderBy: nil];
}


#pragma mark - SELECT > FROM > WHERE > ORDER BY


+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (CBLQueryExpression*)where
                orderBy: (CBLQueryOrderBy*)orderBy
{
    return [[[self class] alloc] initWithSelect: select
                                       distinct: NO
                                           from: from
                                          where: where
                                        orderBy: orderBy];
}


+ (instancetype) selectDistinct: (CBLQuerySelect*)select
                           from: (CBLQueryDataSource*)from
                          where: (CBLQueryExpression*)where
                        orderBy: (CBLQueryOrderBy*)orderBy
{
    return [[[self class] alloc] initWithSelect: select
                                       distinct: YES
                                           from: from
                                          where: where
                                        orderBy: orderBy];
}


- (NSString*) explain: (NSError**)outError {
    if (!_c4Query && ![self check: outError])
        return nil;
    return sliceResult2string(c4query_explain(_c4Query));
}


- (nullable NSEnumerator<CBLQueryRow*>*) run: (NSError**)outError {
    if (!_c4Query && ![self check: outError])
        return nil;
    
    C4QueryOptions options = kC4DefaultQueryOptions;
    NSData* paramJSON = nil;
    
    C4Error c4Err;
    auto e = c4query_run(_c4Query, &options, {paramJSON.bytes, paramJSON.length}, &c4Err);
    if (!e) {
        CBLWarnError(Query, @"CBLQuery failed: %d/%d", c4Err.domain, c4Err.code);
        convertError(c4Err, outError);
        return nullptr;
    }
    return [[CBLQueryEnumerator alloc] initWithQuery: self
                                             c4Query: _c4Query
                                          enumerator: e
                                     returnDocuments: false];
}


- (CBLLiveQuery*) toLive {
    return [[CBLLiveQuery alloc] initWithQuery: [self copy]];
}
            
            
#pragma mark - Internal


- (instancetype) copyWithZone:(NSZone *)zone {
    return [[[self class] alloc] initWithSelect: _select
                                       distinct: _distinct
                                           from: _from
                                          where: _where
                                        orderBy: _orderBy];
}


#pragma mark - Private


- (BOOL) check: (NSError**)outError {
    NSData* jsonData = [self encodeAsJSON: outError];
    if (!jsonData)
        return NO;
    CBLLog(Query, @"Query encoded as %.*s", (int)jsonData.length, (char*)jsonData.bytes);
    
    _database = (CBLDatabase*) _from.source;
    C4Error c4Err;
    auto query = c4query_new(_database.c4db, {jsonData.bytes, jsonData.length}, &c4Err);
    if (!query) {
        convertError(c4Err, outError);
        return NO;
    }
    c4query_free(_c4Query);
    _c4Query = query;
    return YES;
}


- (nullable NSData*) encodeAsJSON: (NSError**)outError {
    return [NSJSONSerialization dataWithJSONObject: [self asJSON] options: 0 error: outError];
}


- (id) asJSON {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    if (_distinct)
        json[@"DISTINCT"] = @(YES);
    
    if (_where)
        json[@"WHERE"] = [_where asJSON];
    
    if (_orderBy) {
        if ([_orderBy isKindOfClass: [CBLQuerySortOrder class]])
            json[@"ORDER_BY"] = @[[_orderBy asJSON]];
        else
            json[@"ORDER_BY"] = [_orderBy asJSON];
    }
    return json;
}

@end
