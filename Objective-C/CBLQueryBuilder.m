//
//  CBLQueryBuilder.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/29/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLQueryBuilder.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryBuilder

#pragma mark - SELECT > FROM


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: nil
                                      where: nil
                                    groupBy: nil
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: nil
                                      where: nil
                                    groupBy: nil
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


#pragma mark - SELECT > FROM > WHERE


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (CBLQueryExpression*)where
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: nil
                                      where: where
                                    groupBy: nil
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (CBLQueryExpression*)where
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: nil
                                      where: where
                                    groupBy: nil
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: nil
                                      where: where
                                    groupBy: groupBy
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: nil
                                      where: where
                                    groupBy: groupBy
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY > HAVING


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
              having: (nullable CBLQueryExpression*)having
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: nil
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: nil
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                      having: (nullable CBLQueryExpression*)having
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: nil
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: nil
                                      limit: nil];
}


#pragma mark - SELECT > FROM > WHERE > ORDER BY


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where
             orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: nil
                                      where: where
                                    groupBy: nil
                                     having: nil
                                    orderBy: orderings
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where
                     orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: nil
                                      where: where
                                    groupBy: nil
                                     having: nil
                                    orderBy: orderings
                                      limit: nil];
}


#pragma mark - SELECT > FROM > WHERE > GROUP BY > HAVING > ORDER BY


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
              having: (nullable CBLQueryExpression*)having
             orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
               limit: (nullable CBLQueryLimit*)limit
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: nil
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: orderings
                                      limit: limit];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                      having: (nullable CBLQueryExpression*)having
                     orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                       limit: (nullable CBLQueryLimit*)limit
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: nil
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: orderings
                                      limit: limit];
}


#pragma mark - SELECT > FROM > JOIN


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: join
                                      where: nil
                                    groupBy: nil
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: join
                                      where: nil
                                    groupBy: nil
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: join
                                      where: where
                                    groupBy: nil
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: join
                                      where: where
                                    groupBy: nil
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE > GROUP BY


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: join
                                      where: where
                                    groupBy: groupBy
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: join
                                      where: where
                                    groupBy: groupBy
                                     having: nil
                                    orderBy: nil
                                      limit: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE > GROUP BY > HAVING


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
              having: (nullable CBLQueryExpression*)having
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: join
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: nil
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                      having: (nullable CBLQueryExpression*)having
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: join
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: nil
                                      limit: nil];
}


#pragma mark - SELECT > FROM > JOIN > WHERE > ORDER BY


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
             orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: join
                                      where: where
                                    groupBy: nil
                                     having: nil
                                    orderBy: orderings
                                      limit: nil];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
                     orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: join
                                      where: where
                                    groupBy: nil
                                     having: nil
                                    orderBy: orderings
                                      limit: nil];
}


#pragma mark -  SELECT > FROM > JOIN > WHERE > GROUP BY> HAVING > ORDER BY


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
              having: (nullable CBLQueryExpression*)having
             orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
               limit: (nullable CBLQueryLimit*)limit
{
    return [[CBLQuery alloc] initWithSelect: select distinct: NO from: from
                                       join: join
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: orderings
                                      limit: limit];
}


+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                      having: (nullable CBLQueryExpression*)having
                     orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                       limit: (nullable CBLQueryLimit*)limit
{
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: join
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: orderings
                                      limit: limit];
}

@end

