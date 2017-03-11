//
//  CBLXQuery.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBLQueryRow, CBLDocument;
@class CBLQuerySelect, CBLQueryDataSource, CBLQueryExpression, CBLQueryOrderBy;


NS_ASSUME_NONNULL_BEGIN


@interface CBLXQuery : NSObject

- (instancetype) init NS_UNAVAILABLE;

// SELECT > FROM
+ (instancetype) select: (CBLQuerySelect*)select from: (CBLQueryDataSource*)from;

+ (instancetype) selectDistict: (CBLQuerySelect*)selectDistict from: (CBLQueryDataSource*)from;

// SELECT > FROM > WHERE
+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where;

+ (instancetype) selectDistict: (CBLQuerySelect*)selectDistict
                          from: (CBLQueryDataSource*)from
                         where: (nullable CBLQueryExpression*)where;

// SELECT > FROM > WHERE > ORDER BY
+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                orderBy: (nullable CBLQueryOrderBy*)orderBy;

+ (instancetype) selectDistict: (CBLQuerySelect*)selectDistict
                          from: (CBLQueryDataSource*)from
                         where: (nullable CBLQueryExpression*)where
                       orderBy: (nullable CBLQueryOrderBy*)orderBy;

- (nullable NSEnumerator<CBLQueryRow*>*) run: (NSError**)error;

@end


NS_ASSUME_NONNULL_END
