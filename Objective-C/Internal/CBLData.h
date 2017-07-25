//
//  CBLData.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLFLDataSource.h"
#import "Fleece.h"
@class CBLDatabase;
@class CBLC4Document;
@protocol CBLObjectChangeListener;

NS_ASSUME_NONNULL_BEGIN


/** A unique object instance that's used as a value in CBLDictionary to represent a removed value. */
extern NSObject * const kCBLRemovedValue;


/** Category methods for value conversions, added to all objects. */
@interface NSObject (CBLConversions)

/** Encodes this object to Fleece. */
- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError;

/** Returns this object represented as a plain Cocoa object, like an NSArray, NSDictionary,
    NSString, etc.
    The default implementation in NSObject just returns self. CBL classes override this. */
- (id) cbl_toPlainObject;

/** Returns this object as it will appear in a Couchbase Lite document, if there's a different
    form for that. For example, converts NSArray to CBLArray.
    For classes that can't be stored in a document, throws an exception. */
- (id) cbl_toCBLObject;

@end


@interface CBLData : NSObject

/** Returns the boolean interpretation of an object.
    nil, NSNull, and NSNumbers with a 0 or NO value are NO. All others are YES. */
+ (BOOL) booleanValueForObject: (id)object;

/** Decodes a Fleece value to an NSObject. Creates CBL containers like CBLDictionary. */
+ (nullable id) fleeceValueToObject: (FLValue)value
                         datasource: (id<CBLFLDataSource>)datasource
                           database: (CBLDatabase*)database;


@end

NS_ASSUME_NONNULL_END
