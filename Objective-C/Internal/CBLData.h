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


/** A unique object instance that's used as a value in CBLMutableDictionary to represent a removed value. */
extern NSObject * const kCBLRemovedValue;


/** Category methods for value conversions, added to all objects. */
@interface NSObject (CBLConversions)

/** Returns this object represented as a plain Cocoa object, like an NSArray, NSDictionary,
    NSString, etc.
    The default implementation in NSObject just returns self. CBL classes override this. */
- (id) cbl_toPlainObject;

/** Returns this object as it will appear in a Couchbase Lite document, if there's a different
    form for that. For example, converts NSArray to CBLMutableArray.
    For classes that can't be stored in a document, throws an exception. */
- (id) cbl_toCBLObject;

@end


#ifdef __cplusplus
namespace cbl {
    bool      asBool    (id);
    NSInteger asInteger (id);
    long long asLongLong(id);
    float     asFloat   (id);
    double    asDouble  (id);
    NSNumber* asNumber  (id);
    NSString* asString  (id);
    NSDate*   asDate    (id);
}
#endif


NS_ASSUME_NONNULL_END
