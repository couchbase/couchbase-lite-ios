//
//  CBLProperties.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLSubdocument;

NS_ASSUME_NONNULL_BEGIN

/** CBLProperties defines a JSON-compatible object, much like an NSMutableDictionary but with
    type-safe accessors. It is implemented by classes CBLDocument and CBLSubdocument. */
@protocol CBLProperties <NSObject>

/** All of the properties contained in this object. */
@property (readwrite, nullable, nonatomic) NSDictionary<NSString*,id>* properties;

#pragma mark - GETTERS

/** Gets an property's value as an object. Returns types NSNull, NSNumber, NSString, NSArray,
    NSDictionary, and CBLBlob, based on the underlying data type; or nil if the property doesn't
    exist. */
- (nullable id) objectForKey: (NSString*)key;

/** Gets a property's value as a boolean.
    Returns YES if the value exists, and is either `true` or a nonzero number. */
- (BOOL) booleanForKey: (NSString*)key;

/** Gets a property's value as an integer.
    Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    Returns 0 if the property doesn't exist or does not have a numeric value. */
- (NSInteger) integerForKey: (NSString*)key;

/** Gets a property's value as a float.
    Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    Returns 0.0 if the property doesn't exist or does not have a numeric value. */
- (float) floatForKey: (NSString*)key;

/** Gets a property's value as a double.
    Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    Returns 0.0 if the property doesn't exist or does not have a numeric value. */
- (double) doubleForKey: (NSString*)key;

/** Gets a property's value as a string.
    Returns nil if the property doesn't exist, or its value is not a string. */
- (nullable NSString*) stringForKey: (NSString*)key;

/** Gets a property's value as an NSDate.
    JSON does not directly support dates, so the actual property value must be a string, which is
    then parsed according to the ISO-8601 date format (the default used in JSON.)
    Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
    NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    without milliseconds. */
- (nullable NSDate*) dateForKey: (NSString*)key;

/** Get a property's value as a Subdocument, which is a mapping object of a Dictionary
    value to provide property type accessors.
    Returns nil if the property doesn't exists, or its value is not a Dictionary. */
- (nullable CBLSubdocument*) subdocumentForKey: (NSString*)key;

#pragma mark - SETTERS

/** Sets a property value by key.
    Allowed value types are NSNull, NSNumber, NSString, NSArray, NSDictionary, NSDate, 
    CBLSubdocument, CBLBlob. NSArrays and NSDictionaries must contain only the above types.
    Setting a nil value will remove the property.
 
    Note:
    * An NSDate object will be converted to an ISO-8601 format string.
    * When setting a subdocument, the subdocument will be set by reference. However,
      if the subdocument has already been set to another key either on the same or different
      document, the value of the subdocument will be copied instead. */
- (void) setObject: (nullable id)value forKey: (NSString*)key;

/** Sets a boolean value by key. */
- (void) setBoolean: (BOOL)value forKey: (NSString*)key;

/** Sets an integer value by key. */
- (void) setInteger: (NSInteger)value forKey: (NSString*)key;

/** Sets a float value by key. */
- (void) setFloat: (float)value forKey: (NSString*)key;

/** Sets a double value by key. */
- (void) setDouble: (double)value forKey: (NSString*)key;

#pragma mark - SUBSCRIPTS

/** Same as objectForKey:. Enables property access by subscript. */
- (nullable id) objectForKeyedSubscript: (NSString*)key;

/** Same as setObject:forKey:. Enables setting properties by subscript. */
- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key;

#pragma mark - OTHERS

/** Removes a property by key. This is the same as setting its value to nil. */
- (void) removeObjectForKey: (NSString*)key;

/** Tests whether a property exists or not.
    This can be less expensive than -objectForKey:, because it does not have to allocate an
    NSObject for the property value. */
- (BOOL) containsObjectForKey: (NSString*)key;

/** Reverts unsaved changes made to the properties. */
- (void) revert;

@end


/** Default implementation of CBLProperties protocol, which defines a JSON-compatible object, much
    like an NSMutableDictionary but with type-safe accessors.
    Abstract superclass of CBLDocument and (soon) CBLSubdocument. */
@interface CBLProperties: NSObject <CBLProperties>

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

// TODO:
// 1. Evaluate get/set Array of a specific type (new API)
// 4. Property complex object (Can be deferred)
// 5. Iterable or ObjC Equivalent (Can be deferred)
