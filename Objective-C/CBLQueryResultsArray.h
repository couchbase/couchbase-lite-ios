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

- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                              count: (NSUInteger)count;

@end
