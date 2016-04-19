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
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBL_RevID.h"
#import "yajl_gen.h"


@implementation CBL_Body
{
    @private
    NSData* _json;
    NSDictionary* _object;
    BOOL _error;
}

- (instancetype) initWithProperties: (UU NSDictionary*)properties {
    NSParameterAssert(properties);
#if DEBUG
    Assert([CBLJSON dataWithJSONObject: properties options: 0 error: NULL] != nil);
#endif
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

- (instancetype) initWithJSON: (NSData*)json
                  addingDocID: (NSString*)docID
                        revID: (CBL_RevID*)revID
                      deleted: (BOOL)deleted
{
    if (json.length < 2) {
        return [self initWithProperties: $dict({@"_id", docID},
                                               {@"_rev", revID.asString},
                                               {@"_deleted", (deleted ? $true : nil)})];
    }

    // Generate JSON data for {"_id":docID,"_rev":revID,"_deleted":deleted} :
    yajl_gen gen = yajl_gen_alloc(NULL);
    yajl_gen_map_open(gen);
    yajl_gen_string(gen, (const unsigned char*)"_id", 3);
    CBLWithStringBytes(docID, ^(const char *chars, size_t len) {
        yajl_gen_string(gen, (const unsigned char*)chars, len);
    });
    yajl_gen_string(gen, (const unsigned char*)"_rev", 4);
    NSData* revIDBytes = revID.asData;
    yajl_gen_string(gen, (const unsigned char*)revIDBytes.bytes, revIDBytes.length);
    if (deleted) {
        yajl_gen_string(gen, (const unsigned char*)"_deleted", 8);
        yajl_gen_bool(gen, true);
    }
    yajl_gen_map_close(gen);

    // Append that JSON to the input:
    const uint8_t* buf;
    size_t len;
    yajl_gen_get_buf(gen, &buf, &len);
    NSData* extra = [[NSData alloc] initWithBytesNoCopy: (void*)buf length: len freeWhenDone: NO];
    self = [self initWithJSON: [CBLJSON appendJSONDictionaryData: extra
                                            toJSONDictionaryData: json]];
    yajl_gen_free(gen);
    return self;
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
            Warn(@"CBL_Body: couldn't parse JSON: %@ (error=%@)", [_json my_UTF8ToString], error.my_compactDescription);
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
- (CBL_RevID*) cbl_rev              {return $castIf(NSString, self[@"_rev"]).cbl_asRevID;}
- (NSString*) cbl_revStr            {return $castIf(NSString, self[@"_rev"]);}
- (BOOL) cbl_deleted                {return $castIf(NSNumber, self[@"_deleted"]).boolValue;}
- (NSDictionary*) cbl_attachments   {return $castIf(NSDictionary, self[@"_attachments"]);}
@end


@implementation NSMutableDictionary (CBL_Body)
- (void) cbl_setID: (UU NSString*)docID rev: (UU CBL_RevID*)revID {
    self[@"_id"] = docID;
    self[@"_rev"] = revID.asString;
}

- (void) cbl_setID: (UU NSString*)docID revStr: (UU NSString*)revIDStr {
    self[@"_id"] = docID;
    self[@"_rev"] = revIDStr;
}

- (void) setCbl_rev: (UU CBL_RevID*)revID   {self[@"_rev"] = revID.asString;}
- (void) setCbl_revStr: (UU NSString*)revID {self[@"_rev"] = revID;}
@end
