//
//  CBLCouchbaseLite.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 4/24/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLCouchbaseLite.h"
#import "CBLLog+Internal.h"

@implementation CBLCouchbaseLite

+ (CBLLog*) log {
    return [CBLLog sharedInstance];
}

@end
