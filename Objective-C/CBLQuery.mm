//
//  CBLQuery.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryEnumerator.h"
#import "CBLCoreBridge.h"
#import "CBLInternal.h"
#import "CBLLiveQuery+Internal.h"
#import "CBLPredicateQuery+Internal.h"
#import "CBLStatus.h"
#import "c4Query.h"


@implementation CBLQuery
{
    C4Query* _c4Query;
}

@synthesize select=_select, from=_from, join=_join;
@synthesize where=_where, orderings=_orderings, groupBy=_groupBy, having=_having;
@synthesize distinct=_distinct;


- (instancetype) initWithSelect: (NSArray<CBLQuerySelectResult*>*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
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
    }
    return self;
}


- (void) dealloc {
    c4query_free(_c4Query);
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
                                        orderBy: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: nil
                                        groupBy: nil
                                         having: nil
                                        orderBy: nil];
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
                                        orderBy: nil];
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
                                        orderBy: nil];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY

+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: nil
                                        orderBy: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: nil
                                        orderBy: nil];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY > HAVING


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: nil];
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
                                        orderBy: orderings];
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
                                        orderBy: orderings];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY > HAVING > ORDER BY


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: orderings];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: nil
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: orderings];
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
                                        orderBy: nil];
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
                                        orderBy: nil];
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
                                        orderBy: nil];
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
                                        orderBy: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE > GROUP BY


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: nil
                                        orderBy: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: nil
                                        orderBy: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE > GROUP BY > HAVING


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: nil];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: nil];
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
                                        orderBy: orderings];
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
                                        orderBy: orderings];
}


#pragma mark -  SELECT > FROM > JOIN > WHERE > GROUP BY> HAVING > ORDER BY


+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: orderings];
}


+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from
                                           join: join
                                          where: where
                                        groupBy: groupBy
                                         having: having
                                        orderBy: orderings];
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


- (CBLDatabase*) database {
    return (CBLDatabase*)_from.source;
}


- (instancetype) copyWithZone:(NSZone *)zone {
    return [[[self class] alloc] initWithSelect: _select
                                       distinct: _distinct
                                           from: _from
                                           join: _join
                                          where: _where
                                        groupBy: _groupBy
                                         having: _having
                                        orderBy: _orderings];
}


#pragma mark - Private


- (BOOL) check: (NSError**)outError {
    NSData* jsonData = [self encodeAsJSON: outError];
    if (!jsonData)
        return NO;
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


- (nullable NSData*) encodeAsJSON: (NSError**)outError {
    return [NSJSONSerialization dataWithJSONObject: [self asJSON] options: 0 error: outError];
}


- (id) asJSON {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    
    if (_distinct)
        json[@"DISTINCT"] = @(YES);
    
    if (_select.count > 0) {
        NSMutableArray* selects = [NSMutableArray array];
        for (CBLQuerySelectResult* select in _select) {
            [selects addObject: [select asJSON]];
        }
        json[@"WHAT"] = selects;
    }
    
    // Join:
    NSMutableArray* from;
    NSDictionary* as = [_from asJSON];
    if (as.count > 0) {
        if (!from)
            from = [NSMutableArray array];
        [from addObject: as];
    } if (_join) {
        if (!from)
            from = [NSMutableArray array];
        for (CBLQueryJoin* j in _join) {
            [from addObject: [j asJSON]];
        }
    }
    if (from.count > 0)
        json[@"FROM"] = from;
    
    if (_where)
        json[@"WHERE"] = [_where asJSON];
    
    if (_groupBy) {
        NSMutableArray* groupBy = [NSMutableArray array];
        for (CBLQueryGroupBy* g in _groupBy) {
            [groupBy addObject: [g asJSON]];
        }
        json[@"GROUP_BY"] = groupBy;
    }
    
    if (_having)
        json[@"HAVING"] = [_having asJSON];
    
    if (_orderings) {
        NSMutableArray* orderBy = [NSMutableArray array];
        for (CBLQueryOrdering* o in _orderings) {
            [orderBy addObject: [o asJSON]];
        }
        json[@"ORDER_BY"] = orderBy;
    }
    
    return json;
}

@end
