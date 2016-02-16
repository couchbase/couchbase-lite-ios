//
//  CBLQueryRow+Router.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/15/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLQuery.h"


@interface CBLQueryRow (Router)

@property (readonly, nonatomic) NSDictionary* asJSONDictionary;

@end
