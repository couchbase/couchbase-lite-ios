//
//  CBLReadOnlyDictionary.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyDictionaryFragment.h"
@class CBLBlob;
@class CBLReadOnlyArray;
@class CBLReadOnlyDictionary;


NS_ASSUME_NONNULL_BEGIN

/** CBLReadOnlyDictionary protocol defines a set of methods for readonly accessing dictionary data. */
@protocol CBLReadOnlyDictionary <NSObject, CBLReadOnlyDictionaryFragment, NSFastEnumeration>

/** The number of entries in the dictionary. */
@property (readonly, nonatomic) NSUInteger count;

// Note:
// The allKeys property is not in the spec yet. Beside the functionality,
// the Swift implementation is also required.
// https://github.com/couchbaselabs/couchbase-lite-apiv2/issues/94

/** An array containing all keys, or an empty array if the dictionary has no entries. */
@property (readonly, copy, nonatomic) NSArray<NSString*>* allKeys;

/** Gets a property's value as an object. The object types are CBLBlob, CBLReadOnlyArray,
    CBLReadOnlyDictionary, NSNumber, or NSString based on the underlying data type; or nil if the
    property value is NSNull or the property doesn't exist. 
    @param key  the key.
    @result the object value or nil. */
- (nullable id) objectForKey: (NSString*)key;

/** Gets a property's value as a boolean.
    Returns YES if the value exists, and is either `true` or a nonzero number. 
    @param key  the key.
    @result the boolean value. */
- (BOOL) booleanForKey: (NSString*)key;

/** Gets a property's value as an integer.
    Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    Returns 0 if the property doesn't exist or does not have a numeric value.
    @param key  the key.
    @result the integer value. */
- (NSInteger) integerForKey: (NSString*)key;

/** Gets a property's value as a float.
    Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    Returns 0.0 if the property doesn't exist or does not have a numeric value. 
    @param key  the key.
    @result the float value. */
- (float) floatForKey: (NSString*)key;

/** Gets a property's value as a double.
    Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    Returns 0.0 if the property doesn't exist or does not have a numeric value. 
    @param key  the key.
    @result the double value. */
- (double) doubleForKey: (NSString*)key;

/** Gets a property's value as a string.
    Returns nil if the property doesn't exist, or its value is not a string. 
    @param key  the key.
    @result the NSString object or nil. */
- (nullable NSString*) stringForKey: (NSString*)key;

/** Gets a property's value as a number.
    Returns nil if the property doesn't exist, or its value is not a number. 
    @param key  the key.
    @result the NSNumber object or nil. */
- (nullable NSNumber*) numberForKey: (NSString*)key;

/** Gets a property's value as an NSDate.
    JSON does not directly support dates, so the actual property value must be a string, which is
    then parsed according to the ISO-8601 date format (the default used in JSON.)
    Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
    NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    without milliseconds. 
    @param key  the key.
    @result the NSDate object or nil. */
- (nullable NSDate*) dateForKey: (NSString*)key;

/** Get a property's value as a CBLBlob.
    Returns nil if the property doesn't exist, or its value is not a CBLBlob. 
    @param key  the key.
    @result the CBLBlob object or nil. */
- (nullable CBLBlob*) blobForKey: (NSString*)key;

/** Get a property's value as a CBLReadOnlyDictionary, which is a mapping object of 
    a dictionary value.
    Returns nil if the property doesn't exists, or its value is not a dictionary.
    @param key  the key.
    @result the CBLReadOnlyDictionary object or nil. */
- (nullable CBLReadOnlyDictionary*) dictionaryForKey: (NSString*)key;

/** Get a property's value as a CBLReadOnlyArray, which is a mapping object of an array value. 
    Returns nil if the property doesn't exists, or its value is not an array. 
    @param key  the key.
    @result the CBLReadOnlyArray object or nil. */
- (nullable CBLReadOnlyArray*) arrayForKey: (NSString*)key;

/** Tests whether a property exists or not.
    This can be less expensive than -objectForKey:, because it does not have to allocate an
    NSObject for the property value. 
    @param key  the key.
    @result the boolean value representing whether a property exists or not. */
- (BOOL) containsObjectForKey: (NSString*)key;

/** Gets content of the current object as an NSDictionary. The values contained in the 
    returned NSDictionary object are JSON based values.
    @result the NSDictionary object representing the content of the current object in the 
            JSON format. */
- (NSDictionary<NSString*,id>*) toDictionary;

@end

/** CBLReadOnlyDictionary provides readonly access to dictionary data. */
@interface CBLReadOnlyDictionary : NSObject <CBLReadOnlyDictionary>

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
