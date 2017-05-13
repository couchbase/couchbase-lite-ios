//
//  CBLDictionary.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyDictionary.h"
#import "CBLDictionaryFragment.h"
@class CBLArray;
@class CBLDictionary;

NS_ASSUME_NONNULL_BEGIN

/** CBLDictionary protocol defines a set of methods for getting and setting dictionary data. */
@protocol CBLDictionary <CBLReadOnlyDictionary, CBLDictionaryFragment>

/** Set a dictionary as a content. Allowed value types are NSArray, NSDate, NSDictionary, NSNumber,
    NSNull, NSString, CBLArray, CBLBlob, CBLDictionary. The NSArrays and NSDictionaries must
    contain only the above types. Setting the new dictionary content will replace the current data
    including the existing CBLArray and CBLDictionary objects.
    @param dictionary  the dictionary. */
- (void) setDictionary: (nullable NSDictionary<NSString*,id>*)dictionary;

/** Set an object value by key. Setting the value to nil will remove the property. Allowed value
    types are NSArray, NSDate, NSDictionary, NSNumber, NSNull, NSString, CBLArray, CBLBlob,
    CBLDictionary. The NSArrays and NSDictionaries must contain only the above types. An NSDate 
    object will be converted to an ISO-8601 format string. 
    @param value    the object value.
    @param key      the key. */
- (void) setObject: (nullable id)value forKey: (NSString*)key;

/** Get a property's value as a CBLArray, which is a mapping object of an array value.
    Returns nil if the property doesn't exists, or its value is not an array.
    @param key  the key.
    @result the CBLArray object or nil if the property doesn't exist. */
- (nullable CBLArray*) arrayForKey: (NSString*)key;

/** Get a property's value as a CBLDictionary, which is a mapping object of a dictionary
    value. Returns nil if the property doesn't exists, or its value is not a dictionary.
    @param key  the key.
    @result the CBLDictionary object or nil if the key doesn't exist. */
- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key;

/** Subscripting access to a CBLFragment object that represents the value of the dictionary by key.
    @param key  the key.
    @result the CBLFragment object. */
- (CBLFragment*) objectForKeyedSubscript: (NSString*)key;

@end

/** CBLDictionary provides access to dictionary data. */
@interface CBLDictionary : CBLReadOnlyDictionary <CBLDictionary>

/** Creates a new empty CBLDictionary object.
    @result the CBLDictionary object. */
+ (instancetype) dictionary;

/** Initialize a new empty CBLDictionary object.
    @result the CBLDictionary object. */
- (instancetype) init;


/** Initialzes a new CBLDictionary object with dictionary content. Allowed value types are NSArray,
    NSDate, NSDictionary, NSNumber, NSNull, NSString, CBLArray, CBLBlob, CBLDictionary.
    The NSArrays and NSDictionaries must contain only the above types.
    @param dictionary   the dictionary object. 
    @result the CBLDictionary object. */
- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary;

@end

NS_ASSUME_NONNULL_END
