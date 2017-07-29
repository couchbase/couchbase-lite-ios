//
//  CBLDatabaseChange.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

/** Database Change information  */
@interface CBLDatabaseChange : NSObject

/** The ID of the document that changed. */
@property (atomic, readonly) NSArray* documentIDs;

/** check whether the changes are from the current database object or not. */
@property (atomic, readonly) BOOL isExternal;

@end
