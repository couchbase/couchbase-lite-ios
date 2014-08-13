//
//  CBLQueryPlanner+Private.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/13/14.
//
//

#import "CBLQueryPlanner.h"


@interface CBLQueryPlanner ()

// These properties show the innards of how the view/query are processed. Not usually needed.
@property (readonly) NSPredicate* mapPredicate;
@property (readonly) NSArray* keyExpressions;
@property (readonly) NSArray* valueTemplate;
@property (readonly) NSExpression* queryStartKey;
@property (readonly) NSExpression* queryEndKey;
@property (readonly) BOOL queryInclusiveStart, queryInclusiveEnd;
@property (readonly) NSArray* sortDescriptors;
@property (readonly) NSPredicate* filter;

@end
