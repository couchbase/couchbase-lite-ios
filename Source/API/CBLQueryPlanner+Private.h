//
//  CBLQueryPlanner+Private.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/13/14.
//
//

#import "CBLQueryPlanner.h"


#if DEBUG

@interface CBLQueryPlanner ()

// These properties show the innards of how the view/query are processed. Not usually needed.
@property (readonly, nonatomic) NSPredicate* mapPredicate;
@property (readonly, nonatomic) NSArray* keyExpressions;
@property (readonly, nonatomic) NSArray* valueTemplate;
@property (readonly, nonatomic) NSExpression* queryStartKey;
@property (readonly, nonatomic) NSExpression* queryEndKey;
@property (readonly, nonatomic) NSExpression* queryKeys;
@property (readonly, nonatomic) BOOL queryInclusiveStart, queryInclusiveEnd;
@property (readonly, nonatomic) NSArray* sortDescriptors;
@property (readonly, nonatomic) NSPredicate* filter;

@end

#endif // DEBUG
