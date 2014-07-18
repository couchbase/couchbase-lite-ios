//
//  CBLJSONReader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/30/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLJSONReader.h"
#import <yajl/yajl_parse.h>


@interface CBLGenericArrayMatcher : CBLJSONArrayMatcher
@end

@interface CBLGenericDictMatcher : CBLJSONDictMatcher
@end


@implementation CBLJSONMatcher

- (bool) matchValue: (id)value          {return false;}
- (CBLJSONArrayMatcher*) startArray     {return [[CBLGenericArrayMatcher alloc] init];}
- (CBLJSONDictMatcher*) startDictionary {return [[CBLGenericDictMatcher alloc] init];}
- (id) end                              {return self;}

@end



@implementation CBLJSONArrayMatcher
@end



@interface CBLJSONDictMatcher ()
@property (readwrite) NSString* key;
@end

@implementation CBLJSONDictMatcher
{
    NSString* _key;
}

@synthesize key=_key;

- (bool) matchValue: (id)value                       {return [self matchValue: value forKey: _key];}
- (bool) matchValue:(id)value forKey: (NSString*)key {return true;}

@end



@implementation CBLGenericArrayMatcher
{
    NSMutableArray* _array;
}

- (id)init {
    self = [super init];
    if (self)
        _array = [[NSMutableArray alloc] init];
    return self;
}

- (bool) matchValue: (id)value {
    [_array addObject: value];
    return true;
}

- (id) end {
    return [_array copy];
}

@end



@implementation CBLGenericDictMatcher
{
    NSMutableDictionary* _dict;
}

- (id)init {
    self = [super init];
    if (self)
        _dict = [[NSMutableDictionary alloc] init];
    return self;
}

- (bool) matchValue: (id)value forKey:(NSString *)key {
    _dict[key] = value;
    return true;
}

- (id) end {
    return [_dict copy];
}

@end



@implementation CBLTemplateMatcher
{
    id _template;
}

- (id)initWithTemplate: (id)template {
    self = [super init];
    if (self) {
        _template = template;
    }
    return self;
}

- (bool) matchValue: (id)value forKey:(NSString *)key {
    return true;
}

- (id) nestedTemplate {
    if (self.key)
        return $castIf(NSDictionary, _template)[self.key];
    else
        return $castIf(NSArray, _template)[0];
}

- (CBLJSONArrayMatcher*) startArray {
    id nestedTemplate = self.nestedTemplate;
    if (nestedTemplate && ![nestedTemplate isKindOfClass: [CBLJSONMatcher class]])
        nestedTemplate = [[CBLTemplateMatcher alloc] initWithTemplate: nestedTemplate];
    return nestedTemplate;
}

- (CBLJSONDictMatcher*) startDictionary {
    id nestedTemplate = self.nestedTemplate;
    if (nestedTemplate && ![nestedTemplate isKindOfClass: [CBLJSONMatcher class]])
        nestedTemplate = [[CBLTemplateMatcher alloc] initWithTemplate: nestedTemplate];
    return nestedTemplate;
}


@end




@implementation CBLJSONReader
{
    yajl_handle _yajl;
    NSMutableArray* _stack;
    CBLJSONMatcher* _matcher;
}


- (instancetype) initWithMatcher: (CBLJSONMatcher*)rootMatcher {
    self = [super init];
    if (self) {
        _yajl = yajl_alloc(&kCallbacks, NULL, (__bridge void*)self);
        if (!_yajl)
            return nil;
        _stack = $marray();
        _matcher = rootMatcher;
        LogTo(CBLJSONMatcher, @"Start with %@", _matcher);
    }
    return self;
}


- (void) dealloc {
    if (_yajl)
        yajl_free(_yajl);
}


- (NSString*) errorString {
    unsigned char* cstr = yajl_get_error(_yajl, false, NULL, 0);
    if (!cstr)
        return nil;
    NSString* error = [NSString stringWithUTF8String: (const char*)cstr];
    yajl_free_error(_yajl, cstr);
    return error;
}


#pragma mark - PARSING:


- (BOOL) parseBytes: (const void*)bytes length: (size_t)length {
    CFRetain((__bridge CFTypeRef)self); // keep self from being released during this call
    BOOL ok = yajl_parse(_yajl, bytes, length) == yajl_status_ok;
    CFRelease((__bridge CFTypeRef)self);
    return ok;
}

- (BOOL) parseData:(NSData *)data {
    CFRetain((__bridge CFTypeRef)self); // keep self from being released during this call
    BOOL ok = yajl_parse(_yajl, data.bytes, data.length) == yajl_status_ok;
    CFRelease((__bridge CFTypeRef)self);
    return ok;
}


- (BOOL) finish {
    CFRetain((__bridge CFTypeRef)self); // keep self from being released during this call
    BOOL ok = yajl_complete_parse(_yajl) == yajl_status_ok;
    CFRelease((__bridge CFTypeRef)self);
    return ok;
}


- (void) push: (CBLJSONMatcher*)matcher {
    if (_matcher)
        [_stack addObject: _matcher];
    _matcher = matcher;
    LogTo(CBLJSONMatcher, @"Pushed %@", matcher);
}

- (void) pop {
    NSUInteger count = _stack.count;
    if (count > 0) {
        _matcher = [_stack lastObject];
        [_stack removeObjectAtIndex: count-1];
    } else {
        Assert(_matcher != nil);
        _matcher = nil;
    }
    LogTo(CBLJSONMatcher, @"Popped: now %@", _matcher);
}

- (CBLJSONMatcher*) matcher {
    return _matcher;
}

- (bool) startArray {
    CBLJSONMatcher* matcher = [_matcher startArray];
    if (!matcher)
        return false;
    [self push: matcher];
    return true;
}

- (bool) startMap {
    CBLJSONMatcher* matcher = [_matcher startDictionary];
    if (!matcher)
        return false;
    [self push: matcher];
    return true;
}


- (bool) matchMapKey: (const unsigned char*)key length: (size_t)length {
    ((CBLJSONDictMatcher*)_matcher).key = [[NSString alloc] initWithBytes: key length: length
                                                                 encoding: NSUTF8StringEncoding];
    return true;
}

- (bool) endArrayOrMap: (BOOL)isMap {
    id result = [_matcher end];
    if (!result)
        return false;
    [self pop];
    return [_matcher matchValue: result];
}


#pragma mark - CALLBACKS:


static inline CBLJSONReader* parserForCtx(void *ctx) {
    return (__bridge CBLJSONReader*)ctx;
}

static inline int checkErr(bool result) {
#if DEBUG
    if (!result)
        Warn(@"CBLJSONMatcher returned an error");
#endif
    return result;
}


static int parsed_null(void * ctx) {
    LogTo(CBLJSONMatcher, @"Match null");
    CBLJSONReader* self = parserForCtx(ctx);
    return checkErr([self.matcher matchValue: [NSNull null]]);
}

static int parsed_boolean(void * ctx, int boolVal) {
    LogTo(CBLJSONMatcher, @"Match %s", (boolVal ?"true" :"false"));
    CBLJSONReader* self = parserForCtx(ctx);
    return checkErr([self.matcher matchValue: [NSNumber numberWithBool: (BOOL)boolVal]]);
}

static int parsed_integer(void * ctx, long long integerVal) {
    LogTo(CBLJSONMatcher, @"Match %lld", integerVal);
    CBLJSONReader* self = parserForCtx(ctx);
    return checkErr([self.matcher matchValue: [NSNumber numberWithLongLong: integerVal]]);
}

static int parsed_double(void * ctx, double doubleVal) {
    LogTo(CBLJSONMatcher, @"Match %g", doubleVal);
    CBLJSONReader* self = parserForCtx(ctx);
    return checkErr([self.matcher matchValue: [NSNumber numberWithDouble: doubleVal]]);
}

static int parsed_string(void * ctx, const unsigned char * stringVal, size_t stringLen) {
    LogTo(CBLJSONMatcher, @"Match \"%.*s\"", (int)stringLen, stringVal);
    CBLJSONReader* self = parserForCtx(ctx);
    NSString* string = [[NSString alloc] initWithBytes: stringVal length: stringLen encoding: NSUTF8StringEncoding];
    return checkErr([self.matcher matchValue: string]);
}

static int parsed_start_array(void * ctx) {
    LogTo(CBLJSONMatcher, @"Start array");
    CBLJSONReader* self = parserForCtx(ctx);
    return checkErr([self startArray]);
}

static int parsed_end_array(void * ctx) {
    LogTo(CBLJSONMatcher, @"End array");
    return checkErr([parserForCtx(ctx) endArrayOrMap: false]);
}

static int parsed_start_map(void * ctx) {
    LogTo(CBLJSONMatcher, @"Start object");
    CBLJSONReader* self = parserForCtx(ctx);
    return checkErr([self startMap]);
}

static int parsed_map_key(void * ctx, const unsigned char * key, size_t stringLen) {
    LogTo(CBLJSONMatcher, @"Object key: \"%.*s\"", (int)stringLen, key);
    return checkErr([parserForCtx(ctx) matchMapKey: key length: stringLen]);
}

static int parsed_end_map(void * ctx) {
    LogTo(CBLJSONMatcher, @"End object");
    return checkErr([parserForCtx(ctx) endArrayOrMap: true]);
}

static const yajl_callbacks kCallbacks = {
    .yajl_null        = &parsed_null,
    .yajl_boolean     = &parsed_boolean,
    .yajl_integer     = &parsed_integer,
    .yajl_double      = &parsed_double,
    .yajl_string      = &parsed_string,
    .yajl_start_array = &parsed_start_array,
    .yajl_end_array   = &parsed_end_array,
    .yajl_start_map   = &parsed_start_map,
    .yajl_map_key     = &parsed_map_key,
    .yajl_end_map     = &parsed_end_map
};

@end




#pragma mark - TESTS:

#if DEBUG

@interface CBL_GenericObjectMatcher : CBLJSONMatcher
@property Class arrayMatcherClass;
@property Class dictMatcherClass;
@end

@implementation CBL_GenericObjectMatcher
{
    id _value;
    Class _arrayMatcherClass, _dictMatcherClass;
}

@synthesize arrayMatcherClass = _arrayMatcherClass;
@synthesize dictMatcherClass = _dictMatcherClass;

- (id)init
{
    self = [super init];
    if (self) {
        _arrayMatcherClass = [CBLGenericArrayMatcher class];
        _dictMatcherClass = [CBLGenericDictMatcher class];
    }
    return self;
}

- (bool) matchValue: (id)value {
    Assert(!_value, @"value already set");
    _value = value;
    return true;
}

- (CBLJSONArrayMatcher*) startArray {
    return [[_arrayMatcherClass alloc] init];
}

- (CBLJSONDictMatcher*) startDictionary {
    return [[_dictMatcherClass alloc] init];
}

- (id) end {
    return _value;
}

@end


TestCase(CBLJSONMatcher) {
    RequireTestCase(CBLJSONMatcher_Object);
}

TestCase(CBLJSONMatcher_Object) {
    NSString* const kJSON = @"{\"foo\": 1, \"bar\": 2}";

    CBL_GenericObjectMatcher* matcher = [[CBL_GenericObjectMatcher alloc] init];

    CBLJSONReader* parser = [[CBLJSONReader alloc] initWithMatcher: matcher];
    CAssert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    CAssert([parser finish]);
    CAssertEqual([matcher end], (@{@"foo": @1, @"bar": @2}));
}


#endif //DEBUG
