//
//  CBL_Body.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Body.h"


@implementation CBL_Body
{
    @private
    NSData* _json;
    NSDictionary* _object;
    BOOL _error;
}

- (instancetype) initWithProperties: (NSDictionary*)properties {
    NSParameterAssert(properties);
    self = [super init];
    if (self) {
        _object = [properties copy];
    }
    return self;
}

- (instancetype) initWithArray: (NSArray*)array {
    return [self initWithProperties: (id)array];
}

- (instancetype) initWithJSON: (NSData*)json {
    self = [super init];
    if (self) {
        _json = json ? [json copy] : [[NSData alloc] init];
    }
    return self;
}

+ (instancetype) bodyWithProperties: (NSDictionary*)properties {
    return [[self alloc] initWithProperties: properties];
}
+ (instancetype) bodyWithJSON: (NSData*)json {
    return [[self alloc] initWithJSON: json];
}

- (id) copyWithZone: (NSZone*)zone {
    CBL_Body* body = [[[self class] allocWithZone: zone] init];
    body->_object = [_object copy];
    body->_json = [_json copy];
    body->_error = _error;
    return body;
}

@synthesize error=_error;

- (BOOL) isValidJSON {
    // Yes, this is just like asObject except it doesn't warn.
    if (!_object && !_error) {
        _object = [[CBLJSON JSONObjectWithData: _json options: 0 error: NULL] copy];
        if (!_object) {
            _error = YES;
        }
    }
    return _object != nil;
}

- (NSData*) asJSON {
    if (!_json && !_error) {
        _json = [[CBLJSON dataWithJSONObject: _object options: 0 error: NULL] copy];
        if (!_json) {
            Warn(@"CBL_Body: couldn't convert to JSON");
            _error = YES;
        }
    }
    return _json;
}

- (NSData*) asPrettyJSON {
    id props = self.asObject;
    if (props) {
        NSData* json = [CBLJSON dataWithJSONObject: props
                                          options: CBLJSONWritingPrettyPrinted
                                            error: NULL];
        if (json) {
            NSMutableData* mjson = [json mutableCopy];
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
        _object = [[CBLJSON JSONObjectWithData: _json options: 0 error: &error] copy];
        if (!_object) {
            Warn(@"CBL_Body: couldn't parse JSON: %@ (error=%@)", [_json my_UTF8ToString], error);
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

- (BOOL) compact {
    (void)[self asJSON];
    if (_error)
        return NO;
    _object = nil;
    return YES;
}

@end



@implementation NSDictionary (CBL_Body)
- (NSString*) cbl_id                {return $castIf(NSString, self[@"_id"]);}
- (NSString*) cbl_rev               {return $castIf(NSString, self[@"_rev"]);}
- (BOOL) cbl_deleted                {return $castIf(NSNumber, self[@"_deleted"]).boolValue;}
- (NSDictionary*) cbl_attachments   {return $castIf(NSDictionary, self[@"_attachments"]);}
@end


