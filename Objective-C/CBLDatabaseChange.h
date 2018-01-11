//
//  CBLDatabaseChange.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase;

/** Database Change information  */
@interface CBLDatabaseChange : NSObject

/** The database. */
@property (readonly, nonatomic) CBLDatabase* database;

/** The ID of the document that changed. */
@property (readonly, nonatomic) NSArray* documentIDs;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end
