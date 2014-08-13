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
@property (readonly) NSArray* sortDescriptors;
@property (readonly) NSPredicate* filter;

@end
