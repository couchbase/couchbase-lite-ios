//
//  CBLFLArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/23/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Fleece+CoreFoundation.h"
@class CBLC4Document;
@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface CBLFLArray : NSObject

@property (nonatomic, readonly, nullable) FLArray array;

@property (nonatomic, readonly) CBLC4Document* c4doc;

@property (nonatomic, readonly) CBLDatabase* database;

- (instancetype) initWithArray: (nullable FLArray) array
                         c4doc: (CBLC4Document*)c4doc
                      database: (CBLDatabase*)database;


@end

NS_ASSUME_NONNULL_END
