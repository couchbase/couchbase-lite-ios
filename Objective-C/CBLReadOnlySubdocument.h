//
//  CBLReadOnlySubdocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyDictionary.h"

/** Readonly version of the CBLSubdocument. */
@interface CBLReadOnlySubdocument : CBLReadOnlyDictionary

- (instancetype) init NS_UNAVAILABLE;

@end
