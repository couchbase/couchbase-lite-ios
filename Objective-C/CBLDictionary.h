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

#pragma mark - Type Setters

/**
 Set a CBLArray object for the given key. A nil value will be converted to an NSNull.
 
 @param value The CBLArray object.
 */
- (void) setArray: (nullable CBLArray*)value forKey: (NSString*)key;

/** 
 Set a CBLBlob object for the given key. A nil value will be converted to an NSNull.
 
 @param value The CBLBolb object.
 */
- (void) setBlob: (nullable CBLBlob*)value forKey: (NSString*)key;

/** 
 Set a boolean value for the given key.
 
 @param value The boolean value.
 */
- (void) setBoolean: (BOOL)value forKey: (NSString*)key;

/** 
 Set a Date object for the given key. A nil value will be converted to an NSNull.
 
 @param value The Date object.
 */
- (void) setDate: (nullable NSDate*)value forKey: (NSString*)key;

/** 
 Set a CBLDictionary object for the given key. A nil value will be converted to an NSNull.
 
 @param value The CBLDictionary object.
 */
- (void) setDictionary: (nullable CBLDictionary*)value forKey: (NSString*)key;

/** 
 Set a double value for the given key.
 
 @param value The double value.
 */
- (void) setDouble: (double)value forKey: (NSString*)key;

/** 
 Set a float value for the given key.
 
 @param value The float value.
 */
- (void) setFloat: (float)value forKey: (NSString*)key;

/** 
 Set an integer value for the given key.
 
 @param value The integer value.
 */
- (void) setInteger: (NSInteger)value forKey: (NSString*)key;

/**
 Set a long long value for the given key.
 
 @param value The long long value.
 */
- (void) setLongLong: (long long)value forKey: (NSString*)key;

/** 
 Set an NSNumber object for the given key. A nil value will be converted to an NSNull.
 
 @param value The NSNumber object.
 */
- (void) setNumber: (nullable NSNumber*)value forKey: (NSString*)key;

/** 
 Set an object value for the given key. Allowed value types are CBLArray, CBLBlob, CBLDictionary,
 NSArray, NSDate, NSDictionary, NSNumber, NSNull, NSString. The NSArrays and NSDictionaries must
 contain only the above types. An NSDate value will be converted to an ISO-8601 format string.
 A nil value will be converted an NSNull.
 
 @param value The object value.
 @param key The key.
 */
- (void) setObject: (nullable id)value forKey: (NSString*)key;

/** 
 Set an String object for the given key. A nil value will be converted to an NSNull.
 
 @param value The String object.
 */
- (void) setString: (nullable NSString*)value forKey: (NSString*)key;

#pragma mark - Setting content with an NSDictionary

/** 
 Set a dictionary as a content. Allowed value types are CBLArray, CBLBlob, CBLDictionary,
 NSArray, NSDate, NSDictionary, NSNumber, NSNull, NSString. The NSArrays and NSDictionaries must
 contain only the above types. Setting the new dictionary content will replace the current data
 including the existing CBLArray and CBLDictionary objects.
 
 @param dictionary The dictionary.
 */
- (void) setDictionary: (nullable NSDictionary<NSString*,id>*)dictionary;

#pragma mark - Removing Entries

/** 
 Removes a given key and its value from the dictionary.
 
 @param key The key.
 */
- (void) removeObjectForKey: (NSString*)key;

#pragma mark - Getting dictionary and array object

/** 
 Get a property's value as a CBLArray, which is a mapping object of an array value.
 Returns nil if the property doesn't exists, or its value is not an array.
 
 @param key The key.
 @return The CBLArray object or nil if the property doesn't exist.
 */
- (nullable CBLArray*) arrayForKey: (NSString*)key;

/** 
 Get a property's value as a CBLDictionary, which is a mapping object of a dictionary
 value. Returns nil if the property doesn't exists, or its value is not a dictionary.
 
 @param key The key.
 @return The CBLDictionary object or nil if the key doesn't exist.
 */
- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key;

#pragma mark - Subscript

/** 
 Subscripting access to a CBLFragment object that represents the value of the dictionary by key.
 
 @param key The key.
 @return The CBLFragment object.
 */
- (CBLFragment*) objectForKeyedSubscript: (NSString*)key;

@end

/** CBLDictionary provides access to dictionary data. */
@interface CBLDictionary : CBLReadOnlyDictionary <CBLDictionary>

#pragma mark - Initializers

/** Creates a new empty CBLDictionary object. */
+ (instancetype) dictionary;

/** Initialize a new empty CBLDictionary object. */
- (instancetype) init;

/** 
 Initialzes a new CBLDictionary object with dictionary content. Allowed value types are NSArray,
 NSDate, NSDictionary, NSNumber, NSNull, NSString, CBLArray, CBLBlob, CBLDictionary.
 The NSArrays and NSDictionaries must contain only the above types.
 
 @param dictionary The dictionary object.
 */
- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary;

@end

NS_ASSUME_NONNULL_END
