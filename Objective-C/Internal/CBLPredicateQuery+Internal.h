//
//  CBLPredicateQuery+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
