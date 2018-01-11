//
//  CBLAuthenticator.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLAuthenticator.h"
#import "CBLAuthenticator+Internal.h"

@implementation CBLAuthenticator

- (instancetype) initWithNone {
    return [super init];
}

- (void) authenticate: (NSMutableDictionary*)options {
    // Subclass should implement this method
}

@end
