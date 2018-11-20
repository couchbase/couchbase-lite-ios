//
//  CBLQuery+JSON.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/19/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLQuery.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLQuery ()

/**
 Encoded representation of the query. Can be used to re-create the query by calling
 -initWithDatabase:JSONRepresentation:.
 */
@property (nonatomic, readonly) NSData* JSONRepresentation;


/**
 Creates a query, given a previously-encoded JSON representation, as from the
 JSONRepresentation property.
 @param database  The database to query.
 @param json  JSON data representing an encoded query description.
 */
- (instancetype) initWithDatabase: (CBLDatabase*)database
               JSONRepresentation: (NSData*)json NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
