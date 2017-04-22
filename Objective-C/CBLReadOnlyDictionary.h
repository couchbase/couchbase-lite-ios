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
@class CBLReadOnlySubdocument;


NS_ASSUME_NONNULL_BEGIN

@protocol CBLReadOnlyDictionary <NSObject, CBLReadOnlyDictionaryFragment>

@property (readonly, nonatomic) NSUInteger count;

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

/** Gets a property's value as a number.
 Returns nil if the property doesn't exist, or its value is not a number. */
- (nullable NSNumber*) numberForKey: (NSString*)key;

/** Gets a property's value as an NSDate.
 JSON does not directly support dates, so the actual property value must be a string, which is
 then parsed according to the ISO-8601 date format (the default used in JSON.)
 Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
 NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
 without milliseconds. */
- (nullable NSDate*) dateForKey: (NSString*)key;

/** Get a property's value as a CBLBlob.
 Returns nil if the property doesn't exist, or its value is not a CBLBlob. */
- (nullable CBLBlob*) blobForKey: (NSString*)key;

/** Get a property's value as a Subdocument, which is a mapping object of a Dictionary
 value to provide property type accessors.
 Returns nil if the property doesn't exists, or its value is not a Dictionary. */
- (nullable CBLReadOnlySubdocument*) subdocumentForKey: (NSString*)key;

/** Get a property's value as an array.
 Returns nil if the property doesn't exists, or its value is not an array. */
- (nullable CBLReadOnlyArray*) arrayForKey: (NSString*)key;

/** Tests whether a property exists or not.
 This can be less expensive than -objectForKey:, because it does not have to allocate an
 NSObject for the property value. */
- (BOOL) containsObjectForKey: (NSString*)key;

- (NSDictionary<NSString*,id>*) toDictionary;

- (NSArray*) allKeys; // TODO: This is temporary until implementing NSFastEnumeration protocol.

@end

@interface CBLReadOnlyDictionary : NSObject <CBLReadOnlyDictionary>

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
