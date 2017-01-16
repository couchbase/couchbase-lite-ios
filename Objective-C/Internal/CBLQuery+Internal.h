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
                                     error: (NSError**)error
    NS_DESIGNATED_INITIALIZER;

/** Just encodes the query into the JSON form parsed by LiteCore. (Exposed for testing.) */
+ (nullable NSData*) encodeQuery: (nullable id)where
                         orderBy: (nullable NSArray*)sortDescriptors
                           error: (NSError**)outError;

@end


@interface CBLQuery (Predicates)

/** Converts an NSPredicate into a JSON-compatible object tree of a LiteCore query. */
+ (id) encodePredicate: (NSPredicate*)pred
                 error: (NSError**)outError;

#if DEBUG // these methods are only for tests
+ (void) dumpPredicate: (NSPredicate*)pred;
+ (NSString*) json5ToJSON: (const char*)json5;
#endif

@end

NS_ASSUME_NONNULL_END
