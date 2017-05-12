//
//  CBLPredicateQuery.mm
//  Couchbase Lite
//
//  Created by Jens Alfke on 11/30/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import "CBLPredicateQuery.h"
#import "CBLPredicateQuery+Internal.h"
#import "CBLInternal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLJSON.h"
#import "CBLStatus.h"
#import "c4Document.h"
#import "c4Query.h"
#import "Fleece.h"
extern "C" {
    #import "MYErrorUtils.h"
}


@implementation CBLPredicateQuery
{
    C4Query* _c4Query;
}

@synthesize database=_db;
@synthesize where=_where, orderBy=_orderBy, groupBy=_groupBy;
@synthesize having=_having, distinct=_distinct, returning=_returning;
@synthesize offset=_offset, limit=_limit, parameters=_parameters;



- (instancetype) initWithDatabase: (CBLDatabase*)db
{
    self = [super init];
    if (self) {
        _db = db;
        _orderBy = @[@"_id"];
        _limit = NSUIntegerMax;
    }
    return self;
}


- (void) dealloc {
    c4query_free(_c4Query);
}


- (void) setWhere: (id)where {
    _where = [where copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}

- (void) setOrderBy: (NSArray*)orderBy {
    _orderBy = [orderBy copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}

- (void) setGroupBy: (NSArray*)groupBy {
    _groupBy = [groupBy copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}

- (void) setHaving: (id)having {
    _having = [having copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}

- (void) setReturning: (NSArray*)returning {
    _returning = [returning copy];
    c4query_free(_c4Query);
    _c4Query = nullptr;
}


- (BOOL) check: (NSError**)outError {
    NSData* jsonData = [self encodeAsJSON: outError];
    if (!jsonData)
        return NO;
    CBLLog(Query, @"Query encoded as %.*s", (int)jsonData.length, (char*)jsonData.bytes);
    C4Error c4Err;
    auto query = c4query_new(_db.c4db, {jsonData.bytes, jsonData.length}, &c4Err);
    if (!query) {
        convertError(c4Err, outError);
        return NO;
    }
    c4query_free(_c4Query);
    _c4Query = query;
    return YES;
}


- (NSString*) explain: (NSError**)outError {
    if (!_c4Query && ![self check: outError])
        return nil;
    return sliceResult2string(c4query_explain(_c4Query));
}


- (NSData*) encodeAsJSON: (NSError**)outError {
    id whereJSON = nil;
    if (_where) {
        whereJSON =  [[self class] encodePredicate: _where error: outError];
        if (!whereJSON)
            return nil;
    }

    NSMutableDictionary* q;
    if ([whereJSON isKindOfClass: [NSDictionary class]]) {
        q = [whereJSON mutableCopy];
    } else {
        q = [NSMutableDictionary new];
        if (whereJSON)
            q[@"WHERE"] = whereJSON;
    }

    if (_distinct) {
        q[@"DISTINCT"] = @YES;
    }

    if (_groupBy) {
        NSArray* group = [[self class] encodeExpressions: _groupBy
                                               aggregate: YES
                                                   error: outError];
        if (!group)
            return nil;
        q[@"GROUP_BY"] = group;
    }

    if (_having) {
        id having =  [[self class] encodePredicate: _having error: outError];
        if (!having)
            return nil;
        q[@"HAVING"] = having;
    }

    if (_orderBy) {
        NSArray* sorts = [[self class] encodeSortDescriptors: _orderBy
                                                       error: outError];
        if (!sorts)
            return nil;
        q[@"ORDER_BY"] = sorts;
    }

    if (_returning) {
        NSArray* select = [[self class] encodeExpressions: _returning
                                                aggregate: YES
                                                    error: outError];
        if (!select)
            return nil;
        q[@"WHAT"] = select;
    }

    return [NSJSONSerialization dataWithJSONObject: q options: 0 error: outError];
}


+ (NSArray*) encodeSortDescriptors: (NSArray*)sortDescriptors error: (NSError**)outError {
    NSMutableArray* sorts = [NSMutableArray new];
    for (id sd in sortDescriptors) {
        bool descending = false;
        id key;
        // Each item of sortDescriptors can be an NSSortDescriptor, NSString or NSExpression:
        if ([sd isKindOfClass: [NSExpression class]]) {
            key = [self encodeExpression: sd aggregate: true error: outError];
        } else {
            NSString* keyStr;
            if ([sd isKindOfClass: [NSString class]]) {
                // As a hack, prefixing string with "-" signals descending order
                descending = [sd hasPrefix: @"-"];
                keyStr = descending ? [sd substringFromIndex: 1] : sd;
            } else {
                Assert([sd isKindOfClass: [NSSortDescriptor class]]);
                descending = ![sd ascending];
                keyStr = [sd key];
            }

            // Convert keyStr to JSON as a rank() call or expression:
            if ([keyStr hasPrefix: @"rank("]) {
                if (![keyStr hasSuffix: @")"])
                    return mkError(outError, @"Invalid rank sort descriptor"), nil;
                NSString* keyPath = [keyStr substringWithRange: {5, [keyStr length] - 6}];
                key = @[@"rank()", @[@".", keyPath]];
            } else {
                NSExpression* expr = [NSExpression expressionWithFormat: keyStr argumentArray: @[]];
                key = [self encodeExpression: expr aggregate: true error: outError];
            }
        }
        if (!key)
            return nil;

        if (descending)
            key = @[@"DESC", key];
        [sorts addObject: key];
    }
    return sorts;
}


- (CBLQueryEnumerator*) startEnumeratorForDocs: (bool)forDocs error: (NSError**)outError {
    if (!_c4Query && ![self check: outError])
        return nullptr;

    C4QueryOptions options = kC4DefaultQueryOptions;
    options.skip = _offset;
    options.limit = _limit;
    NSData* paramJSON = nil;
    if (_parameters.count > 0) {
        paramJSON = [NSJSONSerialization dataWithJSONObject: _parameters
                                                    options: 0
                                                      error: outError];
        if (!paramJSON)
            return nullptr;
    }
    C4Error c4Err;
    auto e = c4query_run(_c4Query, &options, {paramJSON.bytes, paramJSON.length}, &c4Err);
    if (!e) {
        CBLWarnError(Query, @"CBLQuery failed: %d/%d", c4Err.domain, c4Err.code);
        convertError(c4Err, outError);
        return nullptr;
    }
    return [[CBLQueryEnumerator alloc] initWithQuery: self
                                             c4Query: _c4Query
                                          enumerator: e
                                     returnDocuments: forDocs];
}


- (NSEnumerator<CBLQueryRow*>*) run: (NSError**)outError {
    return [self startEnumeratorForDocs: false error: outError];
}


- (nullable NSEnumerator<CBLDocument*>*) allDocuments: (NSError**)outError {
    return [self startEnumeratorForDocs: true error: outError];
}


@end
