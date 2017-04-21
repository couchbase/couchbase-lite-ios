//
//  CBLDictionary.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyDictionary.h"
@class CBLSubdocument;
@class CBLArray;

NS_ASSUME_NONNULL_BEGIN

@protocol CBLDictionary <CBLReadOnlyDictionary>

- (void) setObject: (nullable id)value forKey: (NSString*)key;

/** Sets a boolean value by key. */
- (void) setBoolean: (BOOL)value forKey: (NSString*)key;

/** Sets an integer value by key. */
- (void) setInteger: (NSInteger)value forKey: (NSString*)key;

/** Sets a float value by key. */
- (void) setFloat: (float)value forKey: (NSString*)key;

/** Sets a double value by key. */
- (void) setDouble: (double)value forKey: (NSString*)key;

/** Removes a property by key. This is the same as setting its value to nil. */
- (void) removeObjectForKey: (NSString*)key;

- (nullable CBLSubdocument*) subdocumentForKey: (NSString*)key;

- (nullable CBLArray*) arrayForKey: (NSString*)key;

- (void) setDictionary: (NSDictionary<NSString*,id>*)dictionary;

@end


@interface CBLDictionary : CBLReadOnlyDictionary <CBLDictionary>

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
