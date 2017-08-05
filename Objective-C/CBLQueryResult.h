//
//  CBLQueryResult.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/18/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArray.h"
#import "CBLReadOnlyDictionary.h"

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLQueryResult represents a single row in the query result. The projecting result value
 can be accessed either by using a zero based index or by a key corresponding to the
 CBLQuerySelectResult objects given when constructing the CBLQuery object.
 
 A key used for accessing the projecting result value could be one of the followings:
 * The alias name of the CBLQuerySelectResult object.
 * The last component of the keypath or property name of the property expression used
 when creating the CBLQuerySelectResult object.
 * The provision key in $1, $2, ...$N format for the CBLQuerySelectResult that doesn't have
 an alias name specified or is not a property expression such as an aggregate function
 expression (e.g. count(), avg(), min(), max(), sum() and etc). The number suffix
 after the '$' character is a running number starting from one.
 */
@interface CBLQueryResult : NSObject <CBLReadOnlyArray, CBLReadOnlyDictionary>

/** Not Available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
