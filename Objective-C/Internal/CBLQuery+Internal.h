//
//  CBLQuery+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLQueryRow.h"
#import "c4.h"


NS_ASSUME_NONNULL_BEGIN


#define kBadQuerySpecError -1
#define CBLErrorDomain @"CouchbaseLite"
#define mkError(ERR, FMT, ...)  MYReturnError(ERR, kBadQuerySpecError, CBLErrorDomain, \
                                              FMT, ## __VA_ARGS__)

extern C4LogDomain QueryLog;


@interface CBLQuery ()

/** Initializer. See -[CBLDatabase createQuery:...] for parameter descriptions.
    NOTE: There are some extra undocumented types that `where` accepts:
    * NSArray (interpreted as the WHERE property of a raw LiteCore JSON query)
    * NSDictionary (interpreted as a raw LiteCore JSON query)
    * NSData (pre-encoded JSON query) */
- (instancetype) initWithDatabase: (CBLDatabase*)db;

/** Just encodes the query into the JSON form parsed by LiteCore. (Exposed for testing.) */
- (nullable NSData*) encodeAsJSON: (NSError**)outError;

@end


@interface CBLQuery (Predicates)

/** Converts an NSPredicate into a JSON-compatible object tree of a LiteCore query. */
+ (nullable id) encodePredicate: (id)pred
                          error: (NSError**)error;

+ (nullable id) encodeExpression: (NSExpression*)expr
                       aggregate: (BOOL)aggregate
                           error: (NSError**)outError;

+ (nullable NSArray*) encodeExpressions: (NSArray*)exprs
                              aggregate: (BOOL)aggregate
                                  error: (NSError**)outError;

/** Translates an array of NSExpressions or NSStrings into JSON data. */
+ (nullable NSData*) encodeExpressionsToJSON: (NSArray*)expressions
                                       error: (NSError**)error;

#if DEBUG // these methods are only for tests
+ (void) dumpPredicate: (NSPredicate*)pred;
+ (nullable NSString*) json5ToJSON: (const char*)json5;
#endif

@end


@interface CBLQueryEnumerator : NSEnumerator
- (instancetype) initWithQuery: (CBLQuery*)query
                       c4Query: (C4Query*)c4Query
                    enumerator: (C4QueryEnumerator*)e;

@property (readonly, nonatomic) CBLDatabase* database;
@property (readonly, nonatomic) C4Query* c4Query;
@end


@interface CBLQueryRow ()
- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                       c4Enumerator: (C4QueryEnumerator*)e;
@end


NS_ASSUME_NONNULL_END
