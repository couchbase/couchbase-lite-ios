//
//  CBLQuery.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLLiveQuery+Internal.h"
#import "CBLPropertyExpression.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryResultSet+Internal.h"
#import "CBLStatus.h"
#import "c4Query.h"


@implementation CBLQuery
{
    C4Query* _c4Query;
    NSDictionary* _columnNames;
}

@synthesize select=_select, from=_from, join=_join, where=_where, orderings=_orderings, limit=_limit;
@synthesize groupBy=_groupBy, having=_having;
@synthesize distinct=_distinct;
@synthesize parameters=_parameters;


- (instancetype) initWithSelect: (NSArray<CBLQuerySelectResult*>*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit;
{
    self = [super init];
    if (self) {
        _select = select;
        _distinct = distinct;
        _from = from;
        _join = join;
        _where = where;
        _groupBy = groupBy;
        _having = having;
        _orderings = orderings;
        _limit = limit;
    }
    return self;
}


- (void) dealloc {
    c4query_free(_c4Query);
}


- (NSString*) description {
    NSData* data = [NSJSONSerialization dataWithJSONObject: [self asJSON] options: 0 error: nil];
    NSString* desc = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    return [NSString stringWithFormat: @"%@[json=%@]", self.class, desc];
}


#pragma mark - Parameters


- (CBLQueryParameters*) parameters {
    if (!_parameters) {
        _parameters = [[CBLQueryParameters alloc] initWithParameters: nil];
    }
    return _parameters;
}


#pragma mark - SELECT > FROM


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: nil
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: nil
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


#pragma mark - SELECT > FROM > WHERE


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (CBLQueryExpression*)where
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: where
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (CBLQueryExpression*)where
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: where
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY

+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY > HAVING


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: nil
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: nil
                                          limit: nil];
}


#pragma mark - SELECT > FROM > WHERE > ORDER BY


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: where
                                        groupBy: nil
                                         having: nil
                                        orderBy: orderings
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: where
                                        groupBy: nil
                                         having: nil
                                        orderBy: orderings
                                          limit: nil];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY > HAVING > ORDER BY


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                  limit: (nullable CBLQueryLimit*)limit
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: orderings
                                          limit: limit];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: orderings
                                          limit: limit];
}


#pragma mark - SELECT > FROM > JOIN


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: nil
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: nil
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: where
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: where
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE > GROUP BY


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: nil
                                        orderBy: nil
                                          limit: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE > GROUP BY > HAVING


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: nil
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: nil
                                          limit: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE > ORDER BY


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: where
                                        groupBy: nil
                                         having: nil
                                        orderBy: orderings
                                          limit: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: where
                                        groupBy: nil
                                         having: nil
                                        orderBy: orderings
                                          limit: nil];
}


#pragma mark -  SELECT > FROM > JOIN > WHERE > GROUP BY> HAVING > ORDER BY


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                  limit: (nullable CBLQueryLimit*)limit
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: orderings
                                          limit: limit];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: orderings
                                          limit: limit];
}


- (NSString*) explain: (NSError**)outError {
    if (!_c4Query && ![self check: outError])
        return nil;
    return sliceResult2string(c4query_explain(_c4Query));
}


- (nullable CBLQueryResultSet*) run: (NSError**)outError {
    if (!_c4Query && ![self check: outError])
        return nil;
    
    C4QueryOptions options = kC4DefaultQueryOptions;
    NSData* paramJSON = [_parameters encodeAsJSON: outError];
    if (_parameters && !paramJSON)
        return nil;
    
    C4Error c4Err;
    auto e = c4query_run(_c4Query, &options, {paramJSON.bytes, paramJSON.length}, &c4Err);
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


- (CBLLiveQuery*) toLive {
    return [[CBLLiveQuery alloc] initWithQuery: self];
}


#pragma mark - Internal


- (instancetype) copyWithZone:(NSZone *)zone {
    CBLQuery* q =  [[[self class] alloc] initWithSelect: _select
                                               distinct: _distinct
                                                   from: _from
                                                   join: _join
                                                  where: _where
                                                groupBy: _groupBy
                                                 having: _having
                                                orderBy: _orderings
                                                  limit: _limit];
    q.parameters = [_parameters copy];
    return q;
}


- (CBLDatabase*) database {
    return (CBLDatabase*)_from.source;
}


+ (NSData*) encodeExpressions: (NSArray*)expressions error: (NSError**)outError {
    NSMutableArray* json = [NSMutableArray arrayWithCapacity: expressions.count];
    for (id exp in expressions) {
        if ([exp isKindOfClass: [CBLQueryExpression class]]) {
            [json addObject: [exp asJSON]];
        } else if ([exp isKindOfClass: [NSString class]]) {
            NSExpression* e = [NSExpression expressionWithFormat: exp argumentArray: @[]];
            id encoded = [CBLPredicateQuery encodeExpression: e aggregate: NO error: outError];
            [json addObject: encoded];
        } else if ([exp isKindOfClass: [NSExpression class]]) {
            id encoded = [CBLPredicateQuery encodeExpression: exp aggregate: NO error: outError];
            [json addObject: encoded];
        }
    }
    return [NSJSONSerialization dataWithJSONObject: json options: 0 error: outError];
}


#pragma mark - Private


- (BOOL) check: (NSError**)outError {
    NSData* jsonData = [self encodeAsJSON: outError];
    if (!jsonData)
        return NO;
    
    if (!_columnNames) {
        _columnNames = [self generateColumnNames: outError];
        if (!_columnNames)
            return NO;
    }
    
    CBLLog(Query, @"Query encoded as %.*s", (int)jsonData.length, (char*)jsonData.bytes);
    
    C4Error c4Err;
    auto query = c4query_new(self.database.c4db, {jsonData.bytes, jsonData.length}, &c4Err);
    if (!query) {
        convertError(c4Err, outError);
        return NO;
    }
    c4query_free(_c4Query);
    _c4Query = query;
    return YES;
}


- (NSDictionary*) generateColumnNames: (NSError**)outError {
    NSMutableDictionary* map = [NSMutableDictionary dictionary];
    NSUInteger index = 0;
    NSUInteger provisionKeyIndex = 0;
    
    for (CBLQuerySelectResult* select in _select) {
        NSString* name = select.columnName;
        
        if ([name isEqualToString: kCBLAllPropertiesName])
            name = _from.columnName;
        
        if (!name)
            name = [NSString stringWithFormat:@"$%lu", (unsigned long)(++provisionKeyIndex)];
        
        if ([map objectForKey: name]) {
            NSString* desc = [NSString stringWithFormat: @"Duplicate select result named %@", name];
            createError(kCBLStatusInvalidQuery, desc, outError);
            return nil;
        }
        
        [map setObject: @(index) forKey: name];
        index++;
    }
    
    return map;
}


- (nullable NSData*) encodeAsJSON: (NSError**)outError {
    return [NSJSONSerialization dataWithJSONObject: [self asJSON] options: 0 error: outError];
}


- (id) asJSON {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    
    // DISTINCT:
    if (_distinct)
        json[@"DISTINCT"] = @(YES);
    
    // SELECT:
    if (_select.count > 0) {
        NSMutableArray* selects = [NSMutableArray array];
        for (CBLQuerySelectResult* select in _select) {
            [selects addObject: [select asJSON]];
        }
        json[@"WHAT"] = selects;
    }
    
    // JOIN / FROM:
    NSMutableArray* from;
    NSDictionary* as = [_from asJSON];
    if (as.count > 0) {
        if (!from)
            from = [NSMutableArray array];
        [from addObject: as];
    } if (_join) {
        if (!from)
            from = [NSMutableArray array];
        for (CBLQueryJoin* join in _join) {
            [from addObject: [join asJSON]];
        }
    }
    if (from.count > 0)
        json[@"FROM"] = from;
    
    // WHERE:
    if (_where)
        json[@"WHERE"] = [_where asJSON];
    
    // GROUPBY:
    if (_groupBy) {
        NSMutableArray* groupBy = [NSMutableArray array];
        for (CBLQueryExpression* expr in _groupBy) {
            [groupBy addObject: [expr asJSON]];
        }
        json[@"GROUP_BY"] = groupBy;
    }
    
    // HAVING:
    if (_having)
        json[@"HAVING"] = [_having asJSON];
    
    // ORDERBY:
    if (_orderings) {
        NSMutableArray* orderBy = [NSMutableArray array];
        for (CBLQueryOrdering* o in _orderings) {
            [orderBy addObject: [o asJSON]];
        }
        json[@"ORDER_BY"] = orderBy;
    }
    
    // LIMIT/OFFSET:
    if (_limit) {
        NSArray* limit = [_limit asJSON];
        json[@"LIMIT"] = limit[0];
        if (limit.count > 1)
            json[@"OFFSET"] = limit[1];
    }
    
    return json;
}



@end
