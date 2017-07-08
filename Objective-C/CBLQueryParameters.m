//
//  CBLQueryParameters.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryParameters.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryParameters {
    NSMutableDictionary* _params;
}


- (void) setValue: (id)value forName: (NSString*)name {
    if (!_params) {
        _params = [NSMutableDictionary dictionary];
    }
    if (!value)
        value = [NSNull null]; // Only for Apple platform
    _params[name] = value;
}


#pragma mark - Internal


- (instancetype) initWithParameters: (nullable NSDictionary*)params {
    self = [super init];
    if (self) {
        if (params) {
            _params = [NSMutableDictionary dictionaryWithDictionary: params];
        }
    }
    return self;
}


- (instancetype) copyWithZone:(NSZone *)zone {
    return [[CBLQueryParameters alloc] initWithParameters: _params];
}


- (nullable NSData*) encodeAsJSON: (NSError**)outError {
    if (_params)
        return [NSJSONSerialization dataWithJSONObject: _params options: 0 error: outError];
    else
        return nil;
}


@end
