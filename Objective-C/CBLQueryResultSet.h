//
//  CBLQueryResultSet.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/18/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryResult;

@interface CBLQueryResultSet : NSEnumerator<CBLQueryResult*>

@end
