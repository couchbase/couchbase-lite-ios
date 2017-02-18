//
//  CBLSubdocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLProperties.h"
@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN

@interface CBLSubdocument : CBLProperties

@property (readonly, nonatomic, nullable) CBLDocument* document;

@property (readonly, nonatomic) BOOL exists;

+ (instancetype) subdocument;

- (instancetype) init;

@end

@interface CBLSubdocument (Subscripts)

/** Same as objectForKey: */
- (nullable id) objectForKeyedSubscript: (NSString*)key;

/** Same as setObject:forKey: */
- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key;

@end

NS_ASSUME_NONNULL_END
