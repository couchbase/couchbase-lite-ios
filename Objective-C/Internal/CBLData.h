//
//  CBLData.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Fleece.h"
@class CBLDatabase;
@class CBLC4Document;
@protocol CBLObjectChangeListener;

NS_ASSUME_NONNULL_BEGIN

extern NSObject * const kCBLRemovedValue;

@interface CBLData : NSObject

+ (id) convertValue: (id)value listener: (id<CBLObjectChangeListener>)listener;

+ (BOOL) booleanValueForObject: (id)object;

+ (nullable id) fleeceValueToObject: (FLValue)value
                              c4doc: (CBLC4Document*)c4doc
                           database: (CBLDatabase*)database;


@end

NS_ASSUME_NONNULL_END
