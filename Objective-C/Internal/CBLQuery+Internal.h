//
//  CBLQuery+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"

NS_ASSUME_NONNULL_BEGIN


@interface CBLQuery ()

/** Initializer. See -[CBLDatabase createQuery:...] for parameter descriptions.
    NOTE: There are some extra undocumented types that `where` accepts:
    * NSArray (interpreted as the WHERE property of a raw LiteCore JSON query)
    * NSDictionary (interpreted as a raw LiteCore JSON query)
    * NSData (pre-encoded JSON query) */
- (nullable instancetype) initWithDatabase: (CBLDatabase*)db
                                     where: (nullable id)where
                                   orderBy: (nullable NSArray*)sortDescriptors
                                 returning: (nullable NSArray*)returning
                                     error: (NSError**)error
    NS_DESIGNATED_INITIALIZER;

/** Just encodes the query into the JSON form parsed by LiteCore. (Exposed for testing.) */
+ (nullable NSData*) encodeQuery: (nullable id)where
                         orderBy: (nullable NSArray*)sortDescriptors
                       returning: (nullable NSArray*)returning
                           error: (NSError**)error;

@end


@interface CBLQuery (Predicates)

/** Converts an NSPredicate into a JSON-compatible object tree of a LiteCore query. */
+ (nullable id) encodePredicate: (NSPredicate*)pred
                          error: (NSError**)error;

+ (nullable id) encodeExpression: (NSExpression*)expr
                           error: (NSError**)outError;

+ (nullable NSArray*) encodeExpressions: (NSArray*)exprs
                                  error: (NSError**)outError;

/** Translates an array of NSExpressions into JSON data. */
+ (nullable NSData*) encodeExpressionsToJSON: (NSArray<NSExpression*>*)expressions
                                       error: (NSError**)error;

#if DEBUG // these methods are only for tests
+ (void) dumpPredicate: (NSPredicate*)pred;
+ (nullable NSString*) json5ToJSON: (const char*)json5;
#endif

@end

NS_ASSUME_NONNULL_END
