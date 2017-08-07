//
//  CBLQueryResultArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryResultSet;

@interface CBLQueryResultArray : NSArray

- (instancetype) initWithResultSet: (CBLQueryResultSet*)resultSet count: (NSUInteger)count;

@end
