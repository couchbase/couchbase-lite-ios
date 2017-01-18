//
//  CBLSubdocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLProperties.h"


NS_ASSUME_NONNULL_BEGIN

@interface CBLSubdocument : CBLProperties

- (BOOL) exists;

@end

NS_ASSUME_NONNULL_END
