//
//  CBLFleeceArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Fleece+CoreFoundation.h"
#import "CBLReadOnlyArray.h"
@class CBLC4Document;
@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface CBLFleeceArray : NSObject <CBLReadOnlyArray>

- (instancetype) initWithArray: (FLArray) array
                      document: (CBLC4Document*)document
                      database: (CBLDatabase*)database;

+ (instancetype) withArray: (FLArray) array
                  document: (CBLC4Document*)document
                  database: (CBLDatabase*)database;


+ (instancetype) empty;

@end

NS_ASSUME_NONNULL_END
