//
//  CBLJSONMatcher.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/10/13.
//
//

#import "CBLJSONMatcher.h"
#include <yajl/yajl_parse.h>


static const yajl_callbacks kCallbacks;


@implementation CBLJSONMatcher
{
    @protected
    CBLJSONMatchBlock _onMatch;
    @private
    CBLJSONMatchBoolBlock _onMatchBool;
    CBLJSONMatchIntBlock _onMatchInt;
    CBLJSONMatchDoubleBlock _onMatchDouble;
    CBLJSONMatchStringBlock _onMatchString;
    CBLJSONMatchCStringBlock _onMatchCString;
    CBLJSONMatchNullBlock _onMatchNull;
}

+ (instancetype) boolMatcher: (CBLJSONMatchBoolBlock)onMatch {
    CBLJSONMatcher* matcher = [[self alloc] init];
    matcher.onMatchBool = onMatch;
    return matcher;
}

+ (instancetype) intMatcher: (CBLJSONMatchIntBlock)onMatch {
    CBLJSONMatcher* matcher = [[self alloc] init];
    matcher.onMatchInt = onMatch;
    return matcher;
}

+ (instancetype) doubleMatcher: (CBLJSONMatchDoubleBlock)onMatch {
    CBLJSONMatcher* matcher = [[self alloc] init];
    matcher.onMatchDouble = onMatch;
    return matcher;
}

+ (instancetype) stringMatcher: (CBLJSONMatchStringBlock)onMatch {
    CBLJSONMatcher* matcher = [[self alloc] init];
    matcher.onMatchString = onMatch;
    return matcher;
}


@synthesize onMatch=_onMatch, onMatchBool=_onMatchBool, onMatchInt=_onMatchInt,
            onMatchDouble=_onMatchDouble, onMatchString=_onMatchString,
            onMatchCString=_onMatchCString, onMatchNull=_onMatchNull;

- (bool) matchId: (id)value withParser: (CBLJSONParser*)parser {
    return _onMatch && _onMatch(parser, value);
}

- (bool) matchNullWithParser: (CBLJSONParser*)parser {
    if (_onMatchNull)
        return _onMatchNull(parser);
    else
        return [self matchId: [NSNull null] withParser: parser];
}

- (bool) matchBool: (bool)value withParser: (CBLJSONParser*)parser {
    if (_onMatchBool)
        return _onMatchBool(value, parser);
    else
        return [self matchId: @((BOOL)value) withParser: parser];
}

- (bool) matchInt: (SInt64)value withParser: (CBLJSONParser*)parser {
    if (_onMatchInt)
        return _onMatchInt(value, parser);
    else
        return [self matchDouble: (double)value withParser: parser];
}

- (bool) matchDouble: (double)value withParser: (CBLJSONParser*)parser {
    if (_onMatchDouble)
        return _onMatchDouble((double)value, parser);
    else
        return [self matchId: @(value) withParser: parser];
}

- (bool) matchString: (NSString*)value withParser: (CBLJSONParser*)parser {
    if (_onMatchString)
        return _onMatchString(value, parser);
    else
        return [self matchId: value withParser: parser];
}

- (bool) matchCString: (const UInt8*)chars length: (size_t)length withParser: (CBLJSONParser*)parser {
    if (_onMatchCString)
        return _onMatchCString(chars, length, parser);
    else
        return [self matchString: [[NSString alloc] initWithBytes: chars
                                                           length: length
                                                         encoding: NSUTF8StringEncoding]
                      withParser: parser];
}

- (CBLJSONMatcher*) itemMatcher                 {return nil;}
- (bool) startArray: (CBLJSONParser*)parser     {return false;}
- (bool) startObject: (CBLJSONParser*)parser    {return false;}
- (bool) end: (CBLJSONParser*)parser            {return false;}

@end


@implementation CBLJSONArrayMatcher
{
    CBLJSONStartBlock _onStart;
    CBLJSONMatcher* _itemMatcher;
}

@synthesize onStart=_onStart, itemMatcher=_itemMatcher;

- (bool) matchScalar: (id)value {
    return false;
}

- (bool) startArray: (CBLJSONParser*)parser {
    if (_onStart)
        _onStart(parser);
    return true;
}

- (bool) matchItem: (id)item {
    return true;
}

- (bool) end: (CBLJSONParser*)parser {
    return !_onMatch || _onMatch(parser, nil);
}

@end



@implementation CBLJSONObjectMatcher
{
    NSMutableDictionary* _itemMatchers;
    CBLJSONMatcher* _defaultItemMatcher;
}

@synthesize itemMatchers=_itemMatchers, defaultItemMatcher=_defaultItemMatcher;

- (instancetype) init {
    self = [super init];
    if (self) {
        _itemMatchers = $mdict();
    }
    return self;
}

- (bool) startObject: (CBLJSONParser*)parser  {return true;}


- (CBLJSONMatcher*) matcherForKey: (const UInt8*)chars length: (size_t)length {
    NSString* key =  [[NSString alloc] initWithBytes: chars length: length
                                            encoding: NSUTF8StringEncoding];
    return _itemMatchers[key] ?: _defaultItemMatcher;
}

- (bool) end: (CBLJSONParser*)parser {
    return !_onMatch || _onMatch(parser, nil);
}

@end



@implementation CBLJSONParser
{
    yajl_handle _yajl;
    NSMutableArray* _stack;
    CBLJSONMatcher* _matcher;
    CBLJSONMatcher* _rootMatcher;
    CBLJSONMatcher* _nextItemMatcher;
    id _key;
}


- (instancetype) initWithMatcher: (CBLJSONMatcher*)rootMatcher {
    self = [super init];
    if (self) {
        _yajl = yajl_alloc(&kCallbacks, NULL, (__bridge void*)self);
        if (!_yajl)
            return nil;
        _stack = $marray();
        _rootMatcher = rootMatcher;
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


- (CBLJSONMatcher*) currentMatcher {return _matcher;}
- (CBLJSONMatcher*) parentMatcher  {return _stack.lastObject;}


#pragma mark - PARSING:


- (BOOL) parseBytes: (const void*)bytes length: (size_t)length {
    return yajl_parse(_yajl, bytes, length) == yajl_status_ok;
}

- (BOOL) parseData:(NSData *)data {
    return yajl_parse(_yajl, data.bytes, data.length) == yajl_status_ok;
}


- (BOOL) finish {
    return yajl_complete_parse(_yajl) == yajl_status_ok;
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

- (CBLJSONMatcher*) scalarMatcher {
    CBLJSONMatcher* matcher = _nextItemMatcher;
    if (matcher)
        _nextItemMatcher = nil;
    else if (_matcher)
        matcher = _matcher.itemMatcher;
    else
        matcher = _rootMatcher;
    return matcher;
}


- (CBLJSONMatcher*) startItem {
    CBLJSONMatcher* matcher = self.scalarMatcher;
    if (matcher)
        [self push: matcher];
    return matcher;
}

- (bool) matchMapKey: (const unsigned char*)key length: (size_t)length {
    _nextItemMatcher = [(CBLJSONObjectMatcher*)_matcher matcherForKey: key length: length];
    return _nextItemMatcher != nil;
}

- (bool) endArrayOrMap {
    if (![_matcher end: self])
        return false;
    [self pop];
    return true;
}


#pragma mark - CALLBACKS:


static inline CBLJSONParser* parserForCtx(void *ctx) {
    return (__bridge CBLJSONParser*)ctx;
}


static int parsed_null(void * ctx) {
    LogTo(CBLJSONMatcher, @"Match null");
    CBLJSONParser* self = parserForCtx(ctx);
    return [self.scalarMatcher matchNullWithParser: self];
}

static int parsed_boolean(void * ctx, int boolVal) {
    LogTo(CBLJSONMatcher, @"Match %s", (boolVal ?"true" :"false"));
    CBLJSONParser* self = parserForCtx(ctx);
    return [self.scalarMatcher matchBool: boolVal withParser: self];
}

static int parsed_integer(void * ctx, long long integerVal) {
    LogTo(CBLJSONMatcher, @"Match %lld", integerVal);
    CBLJSONParser* self = parserForCtx(ctx);
    return [self.scalarMatcher matchInt: integerVal withParser: self];
}

static int parsed_double(void * ctx, double doubleVal) {
    LogTo(CBLJSONMatcher, @"Match %g", doubleVal);
    CBLJSONParser* self = parserForCtx(ctx);
    return [self.scalarMatcher matchDouble: doubleVal withParser: self];
}

static int parsed_string(void * ctx, const unsigned char * stringVal, size_t stringLen) {
    LogTo(CBLJSONMatcher, @"Match \"%.*s\"", (int)stringLen, stringVal);
    CBLJSONParser* self = parserForCtx(ctx);
    return [self.scalarMatcher matchCString: stringVal length: stringLen withParser: self];
}

static int parsed_start_array(void * ctx) {
    LogTo(CBLJSONMatcher, @"Start array");
    CBLJSONParser* self = parserForCtx(ctx);
    return [[self startItem] startArray: self];
}

static int parsed_end_array(void * ctx) {
    LogTo(CBLJSONMatcher, @"End array");
    return [parserForCtx(ctx) endArrayOrMap];
}

static int parsed_start_map(void * ctx) {
    LogTo(CBLJSONMatcher, @"Start object");
    CBLJSONParser* self = parserForCtx(ctx);
    return [[self startItem] startObject: self];
}

static int parsed_map_key(void * ctx, const unsigned char * key, size_t stringLen) {
    LogTo(CBLJSONMatcher, @"Object key: \"%.*s\"", (int)stringLen, key);
    return [parserForCtx(ctx) matchMapKey: key length: stringLen];
}

static int parsed_end_map(void * ctx) {
    LogTo(CBLJSONMatcher, @"End object");
    return [parserForCtx(ctx) endArrayOrMap];
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


TestCase(CBLJSONMatcher_ArrayOfNumbers) {
    __block struct {
        double numbers[10];
        unsigned n;
    } result;
    result.n = 0;
    __block unsigned numArrays = 0;

    // Build a matcher to parse an array of numbers:
    CBLJSONMatcher* numMatcher = [CBLJSONMatcher intMatcher: ^bool(SInt64 n, CBLJSONParser* p) {
        result.numbers[result.n++] = n;
        return true;
    }];

    CBLJSONArrayMatcher* arrayMatcher = [[CBLJSONArrayMatcher alloc] init];
    arrayMatcher.itemMatcher = numMatcher;
    arrayMatcher.onStart = ^(CBLJSONParser* p){
        result.n = 0;
    };
    arrayMatcher.onMatch = ^bool(id value, CBLJSONParser* p) {
        Log(@"Matched an array, now checking it");
        CAssertEq(result.n, 3u);
        CAssertEq(result.numbers[0], 1);
        CAssertEq(result.numbers[1], 2);
        CAssertEq(result.numbers[2], 99);
        ++numArrays;
        return true;
    };

    CBLJSONParser* parser = [[CBLJSONParser alloc] initWithMatcher: arrayMatcher];
    CAssert([parser parseData: [@"[1, 2, 99]" dataUsingEncoding: NSUTF8StringEncoding]]);
    CAssert([parser finish]);
    CAssertEq(numArrays, 1u);

    // Now parse an array of those arrays:
    CBLJSONArrayMatcher* outerArrayMatcher = [[CBLJSONArrayMatcher alloc] init];
    outerArrayMatcher.itemMatcher = arrayMatcher;

    parser = [[CBLJSONParser alloc] initWithMatcher: outerArrayMatcher];
    numArrays = 0;
    CAssert([parser parseData: [@"[[1, 2, 99],[1, 2, 99]]" dataUsingEncoding: NSUTF8StringEncoding]]);
    CAssert([parser finish]);
    CAssertEq(numArrays, 2u);
}

TestCase(CBLJSONMatcher_Object) {
    NSString* const kJSON = @"{\"foo\": 1, \"bar\": 2}";

    __block NSInteger foo = NSNotFound, bar = NSNotFound;

    CBLJSONObjectMatcher* objectMatcher = [[CBLJSONObjectMatcher alloc] init];
    objectMatcher.itemMatchers[@"foo"] = [CBLJSONMatcher intMatcher: ^bool(SInt64 n, CBLJSONParser* p) {
        foo = n;
        return true;
    }];
    objectMatcher.itemMatchers[@"bar"] = [CBLJSONMatcher intMatcher: ^bool(SInt64 n, CBLJSONParser* p) {
        bar = n;
        return true;
    }];
    __block bool onMatchedCalled = false;
    objectMatcher.onMatch = ^bool(id value, CBLJSONParser* p) {
        Log(@"Matched an object, now checking it");
        CAssert(!onMatchedCalled);
        onMatchedCalled = true;
        CAssertEq(foo, 1);
        CAssertEq(bar, 2);
        return true;
    };

    CBLJSONParser* parser = [[CBLJSONParser alloc] initWithMatcher: objectMatcher];
    CAssert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    CAssert([parser finish]);
    CAssert(onMatchedCalled);
}

TestCase(CBLJSONMatcher) {
    RequireTestCase(CBLJSONMatcher_ArrayOfNumbers);
    RequireTestCase(CBLJSONMatcher_Object);
}