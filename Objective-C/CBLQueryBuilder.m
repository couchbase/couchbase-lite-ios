//
//  CBLQueryBuilder.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

#import "CBLQueryBuilder.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryBuilder

#pragma mark - SELECT > FROM


+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
{
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
               where: (nullable CBLQueryExpression*)where
{
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
                       where: (nullable CBLQueryExpression*)where
{
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
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
    CBLAssertNotNil(select);
    CBLAssertNotNil(from);
    
    return [[CBLQuery alloc] initWithSelect: select distinct: YES from: from
                                       join: join
                                      where: where
                                    groupBy: groupBy
                                     having: having
                                    orderBy: orderings
                                      limit: limit];
}

@end

