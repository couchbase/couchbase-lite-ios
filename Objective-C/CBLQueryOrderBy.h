//
//  CBLQueryOrderBy.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQuerySortOrder, CBLQueryExpression;

@interface CBLQueryOrderBy : NSObject

+ (CBLQueryOrderBy *) orderBy:(CBLQueryOrderBy *)orderBy, ...;

// TODO: [Pasin] I am thinking this would be convenient for most uses of
// ORDER BY. Adding this for now to try.
// NOTE: We also need the property:from: as well when we implement JOIN.
+ (CBLQuerySortOrder *) property: (NSString*)name;

+ (CBLQuerySortOrder *) expression: (CBLQueryExpression*)expression;

@end

@interface CBLQuerySortOrder : CBLQueryOrderBy

- (CBLQueryOrderBy *) ascending;
- (CBLQueryOrderBy *) descending;

@end
