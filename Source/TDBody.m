//
//  TDBody.m
//  TouchDB
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDBody.h"


@implementation TDBody

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

+ (TDBody*) bodyWithProperties: (NSDictionary*)properties {
    return [[[self alloc] initWithProperties: properties] autorelease];
}
+ (TDBody*) bodyWithJSON: (NSData*)json {
    return [[[self alloc] initWithJSON: json] autorelease];
}

@synthesize error=_error;

- (BOOL) isValidJSON {
    // Yes, this is just like asObject except it doesn't warn.
    if (!_object && !_error) {
        _object = [[TDJSON JSONObjectWithData: _json options: 0 error: NULL] copy];
        if (!_object) {
            _error = YES;
        }
    }
    return _object != nil;
}

- (NSData*) asJSON {
    if (!_json && !_error) {
        _json = [[TDJSON dataWithJSONObject: _object options: 0 error: NULL] copy];
        if (!_json) {
            Warn(@"TDBody: couldn't convert to JSON");
            _error = YES;
        }
    }
    return _json;
}

- (NSData*) asPrettyJSON {
    id props = self.asObject;
    if (props) {
        NSData* json = [TDJSON dataWithJSONObject: props
                                          options: TDJSONWritingPrettyPrinted
                                            error: NULL];
        if (json) {
            NSMutableData* mjson = [[json mutableCopy] autorelease];
            [mjson appendBytes: "\n" length: 1];
            return mjson;
        }
    }
    return self.asJSON;
}

- (NSString*) asJSONString {
    return self.asJSON.my_UTF8ToString;
}

- (id) asObject {
    if (!_object && !_error) {
        NSError* error = nil;
        _object = [[TDJSON JSONObjectWithData: _json options: 0 error: &error] copy];
        if (!_object) {
            Warn(@"TDBody: couldn't parse JSON: %@ (error=%@)", [_json my_UTF8ToString], error);
            _error = YES;
        }
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

- (id) objectForKeyedSubscript: (NSString*)key {
    return (self.properties)[key];
}

@end
