//
//  CLDocument.m
//  ToyCouch
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright 2010 Jens Alfke. All rights reserved.
//

#import "CLDocument.h"


@implementation CLDocument

- (id) initWithProperties: (NSDictionary*)properties {
    NSParameterAssert(properties);
    self = [super init];
    if (self) {
        _properties = [properties copy];
    }
    return self;
}

- (id) initWithJSON: (NSData*)json {
    NSParameterAssert(json);
    self = [super init];
    if (self) {
        _json = [json copy];
    }
    return self;
}

- (void)dealloc {
    [_properties release];
    [_json release];
    [_error release];
    [super dealloc];
}

@synthesize error = _error;

- (NSData*) asJSON {
    if (!_json && !_error) {
        NSError* error;
        _json = [[NSJSONSerialization dataWithJSONObject: _properties options: 0 error: &error] copy];
        if (!_json)
            _error = [error retain];
    }
    return _json;
}

- (NSDictionary*) properties {
    if (!_properties && !_error) {
        NSError* error;
        _properties = [[NSJSONSerialization JSONObjectWithData: _json options: 0 error: &error] copy];
        if (!_properties)
            _error = [error retain];
        // FIX: Reject _properties if it's not a dictionary
    }
    return _properties;
}

- (id) propertyForKey: (NSString*)key {
    return [self.properties objectForKey: key];
}

- (NSString*) documentID {
    return [self.properties objectForKey: @"_id"];
}

- (NSString*) revisionID {
    return [self.properties objectForKey: @"_rev"];
}

@end
