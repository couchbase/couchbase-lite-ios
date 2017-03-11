//
//  CBLXQuery.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLXQuery.h"
#import "CBLQuery.h"
#import "CBLXQuery+Internal.h"

@implementation CBLXQuery

@synthesize select=_select, from=_from, where=_where, orderBy=_orderBy, distinct=_distinct;


- (instancetype) initWithSelect: (CBLQuerySelect*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        orderBy: (nullable CBLQueryOrderBy*)orderBy
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


+ (instancetype) select: (CBLQuerySelect*)select from: (CBLQueryDataSource*)from {
    return [[[self class] alloc] initWithSelect: select
                                       distinct: NO
                                           from: from
                                          where: nil
                                        orderBy: nil];
}


+ (instancetype) selectDistict: (CBLQuerySelect*)select from: (CBLQueryDataSource*)from {
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from where: nil orderBy: nil];
}


#pragma mark - SELECT > FROM > WHERE


+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (CBLQueryExpression*)where
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from where: where orderBy: nil];
}


+ (instancetype) selectDistict: (CBLQuerySelect*)select
                          from: (CBLQueryDataSource*)from
                         where: (CBLQueryExpression*)where
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from where: where orderBy: nil];
}


#pragma mark - SELECT > FROM > WHERE > ORDER BY


+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (CBLQueryExpression*)where
                orderBy: (CBLQueryOrderBy*)orderBy
{
    return [[[self class] alloc] initWithSelect: select distinct: NO from: from where: where orderBy: orderBy];
}


+ (instancetype) selectDistict: (CBLQuerySelect*)select
                          from: (CBLQueryDataSource*)from
                         where: (CBLQueryExpression*)where
                       orderBy: (CBLQueryOrderBy*)orderBy
{
    return [[[self class] alloc] initWithSelect: select distinct: YES from: from where: where orderBy: orderBy];
}


#pragma mark - RUN


- (nullable NSEnumerator<CBLQueryRow*>*) run: (NSError**)error {
    id where = nil;
    if ([self.where conformsToProtocol:@protocol(CBLNSPredicateCoding)])
        where = [self.where performSelector: @selector(asNSPredicate)];
    else {
        // TODO: return unsupported error
    }
    
    CBLDatabase*db = (CBLDatabase*)self.from.source;
    CBLQuery* q = [db createQueryWhere: where];
    q.distinct = self.distinct;
    q.orderBy = [self.orderBy asSortDescriptors];
    
    NSLog(@"%@", [q explain:nil]);
    return [q run: error];
}

@end
