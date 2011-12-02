//
//  CLDocument.m
//  ToyCouch
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright 2010 Jens Alfke. All rights reserved.
//

#import "ToyDocument.h"


@implementation ToyDocument

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
    [_error release];
    [super dealloc];
}

+ (ToyDocument*) documentWithProperties: (NSDictionary*)properties {
    return [[[self alloc] initWithProperties: properties] autorelease];
}
+ (ToyDocument*) documentWithJSON: (NSData*)json {
    return [[[self alloc] initWithJSON: json] autorelease];
}

@synthesize error = _error;

- (NSData*) asJSON {
    if (!_json && !_error) {
        NSError* error;
        _json = [[NSJSONSerialization dataWithJSONObject: _object options: 0 error: &error] copy];
        if (!_json)
            _error = [error retain];
    }
    return _json;
}

- (id) asObject {
    if (!_object && !_error) {
        NSError* error;
        _object = [[NSJSONSerialization JSONObjectWithData: _json options: 0 error: &error] copy];
        if (!_object)
            _error = [error retain];
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

- (NSString*) documentID {
    return [self.properties objectForKey: @"_id"];
}

- (NSString*) revisionID {
    return [self.properties objectForKey: @"_rev"];
}

@end
