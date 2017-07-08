//
//  CBLQueryParameters.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** A CBLQueryParameters object used for setting values to the query parameters defined
    in the query. */
@interface CBLQueryParameters : NSObject

/** Set the value to the query parameter referenced by the given name. A query parameter 
    is defined by using the CBLQueryExpression's + parameterNamed: method. */
- (void) setValue: (nullable id)value forName: (NSString*)name;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

