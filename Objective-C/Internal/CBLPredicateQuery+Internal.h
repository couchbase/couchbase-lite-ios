//
//  CBLPredicateQuery+Internal.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLPredicateQuery.h"
#import "CBLQueryRow.h"
#import "CBLErrors.h"
#import "c4.h"
@class CBLQueryEnumerator;


NS_ASSUME_NONNULL_BEGIN


#define mkError(ERR, FMT, ...)  MYReturnError(ERR, CBLErrorInvalidQuery, CBLErrorDomain, \
                                              FMT, ## __VA_ARGS__)

/** Used by CBLQueryEnumerator) */
@protocol CBLQueryInternal <NSObject>
@property (readonly, nonatomic) CBLDatabase* database;
@end

@interface CBLPredicateQuery () <CBLQueryInternal>

/** Initializer. See -[CBLDatabase createQuery:...] for parameter descriptions.
    NOTE: There are some extra undocumented types that `where` accepts:
    * NSArray (interpreted as the WHERE property of a raw LiteCore JSON query)
    * NSDictionary (interpreted as a raw LiteCore JSON query)
    * NSData (pre-encoded JSON query) */
- (instancetype) initWithDatabase: (CBLDatabase*)db;

/** Just encodes the query into the JSON form parsed by LiteCore. (Exposed for testing.) */
- (nullable NSData*) encodeAsJSON: (NSError**)outError;

#if DEBUG
@property (nonatomic) bool disableOffsetAndLimit;   // for testing only
#endif
@end


@interface CBLPredicateQuery (Predicates)

/** Converts an NSPredicate into a JSON-compatible object tree of a LiteCore query. */
+ (nullable id) encodePredicate: (id)pred
                          error: (NSError**)error;

+ (nullable id) encodeExpression: (NSExpression*)expr
                       aggregate: (BOOL)aggregate
                           error: (NSError**)outError;

+ (nullable NSArray*) encodeExpressions: (NSArray*)exprs
                              aggregate: (BOOL)aggregate
                              collation: (BOOL)collation
                                  error: (NSError**)outError;

/** Translates an array of NSExpressions or NSStrings into JSON data. */
+ (nullable NSData*) encodeExpressionsToJSON: (NSArray*)expressions
                                       error: (NSError**)error;

+ (nullable NSArray*) encodeSortDescriptors: (NSArray*)sortDescriptors
                                      error: (NSError**)outError;

#if DEBUG // these methods are only for tests
+ (void) dumpPredicate: (NSPredicate*)pred;
+ (nullable NSString*) json5ToJSON: (const char*)json5;
#endif

@end


@interface CBLQueryRow ()
- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                       c4Enumerator: (C4QueryEnumerator*)e;
- (void) stopBeingCurrent;
@end


NS_ASSUME_NONNULL_END
