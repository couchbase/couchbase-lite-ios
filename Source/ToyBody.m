//
//  ToyBody.m
//  ToyCouch
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyBody.h"


@implementation ToyBody

- (id) initWithProperties: (NSDictionary*)properties {
    NSParameterAssert(properties);
    self = [super init];
    if (self) {
        _object = [properties copy];
    }
    return self;
}

- (id) initWithArray: (NSArray*)array {
    return [self initWithProperties: (id)array];
}

- (id) initWithJSON: (NSData*)json {
    self = [super init];
    if (self) {
        _json = json ? [json copy] : [[NSData alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_object release];
    [_json release];
    [super dealloc];
}

+ (ToyBody*) bodyWithProperties: (NSDictionary*)properties {
    return [[[self alloc] initWithProperties: properties] autorelease];
}
+ (ToyBody*) bodyWithJSON: (NSData*)json {
    return [[[self alloc] initWithJSON: json] autorelease];
}

@synthesize error=_error;

- (NSData*) asJSON {
    if (!_json && !_error) {
        _json = [[NSJSONSerialization dataWithJSONObject: _object options: 0 error: nil] copy];
        if (!_json)
            _error = YES;
    }
    return _json;
}

- (id) asObject {
    if (!_object && !_error) {
        _object = [[NSJSONSerialization JSONObjectWithData: _json options: 0 error: nil] copy];
        if (!_object)
            _error = YES;
    }
    return _object;
}

- (NSDictionary*) properties {
    id object = self.asObject;
    if ([object isKindOfClass: [NSDictionary class]])
        return object;
    else
        return nil;
}

- (id) propertyForKey: (NSString*)key {
    return [self.properties objectForKey: key];
}

@end
