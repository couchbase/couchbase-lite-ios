//
//  CBLQueryBuilder+Private.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/13/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

#import "CBLQueryBuilder.h"


#if DEBUG

@interface CBLQueryBuilder ()

// These properties show the innards of how the view/query are processed. Not usually needed.
@property (readonly, nonatomic) NSPredicate* mapPredicate;
@property (readonly, nonatomic) NSString* docType;
@property (readonly, nonatomic) NSExpression* keyExpression;
@property (readonly, nonatomic) NSExpression* valueExpression;
@property (readonly, nonatomic) NSExpression* queryStartKey;
@property (readonly, nonatomic) NSExpression* queryEndKey;
@property (readonly, nonatomic) NSExpression* queryKeys;
@property (readonly, nonatomic) BOOL queryInclusiveStart, queryInclusiveEnd;
@property (readonly, nonatomic) NSArray* sortDescriptors;
@property (readonly, nonatomic) NSPredicate* filter;

@end

#endif // DEBUG
