//
//  CBLFleeceDictionary.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import <Foundation/Foundation.h>
#import "Fleece+CoreFoundation.h"
#import "CBLReadOnlyDictionary.h"
@class CBLC4Document;
@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface CBLFleeceDictionary: NSObject <CBLReadOnlyDictionary>

- (instancetype) initWithDict: (nullable FLDict) dict
                     document: (CBLC4Document*)document
                     database: (CBLDatabase*)database;

+ (instancetype) withDict: (nullable FLDict) dict
                 document: (CBLC4Document*)document
                 database: (CBLDatabase*)database;

+ (instancetype) empty;

@end

NS_ASSUME_NONNULL_END
