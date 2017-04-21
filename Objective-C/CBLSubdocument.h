//
//  CBLSubdocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDictionary.h"
#import "CBLReadOnlySubdocument.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLSubdocument : CBLReadOnlySubdocument <CBLDictionary>

+ (instancetype) subdocument;

- (instancetype) init;

- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary;

@end

/** Define Subscription methods for CBLDocument. */
@interface CBLSubdocument (Subscripts)

/** Same as objectForKey: */
 - (nullable id) objectForKeyedSubscript: (NSString*)key;

/** Same as setObject:forKey: */
 - (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key;

@end

NS_ASSUME_NONNULL_END
