//
//  CBLQueryResultsArray.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryEnumerator;

@interface CBLQueryResultsArray : NSArray

// TODO: We should define a protocol here:
- (instancetype) initWithEnumerator: (id)enumerator
                              count: (NSUInteger)count;

@end
