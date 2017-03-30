//
//  CBLQuery.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLPredicateQuery.h"
#import "CBLQuery+Internal.h"


@implementation CBLQuery {
    CBLPredicateQuery* _query;
}


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


- (BOOL) check: (NSError**)outError {
    return [[self query] check: outError];
}


- (nullable NSString*) explain: (NSError**)outError {
    return [[self query] explain: outError];
}


- (nullable NSEnumerator<CBLQueryRow*>*) run: (NSError**)outError {
    return [[self query] run: outError];
}


#pragma mark - PRIVATE


- (CBLPredicateQuery*) query {
    if (!_query) {
        id where = nil;
        if ([self.where conformsToProtocol: @protocol(CBLNSPredicateCoding)])
            where = [(id)self.where asNSPredicate];
        
        CBLDatabase*db = (CBLDatabase*)self.from.source;
        _query = [db createQueryWhere: where];
        _query.distinct = self.distinct;
        _query.orderBy = [self.orderBy asSortDescriptors];
    }
    return _query;
}


@end
