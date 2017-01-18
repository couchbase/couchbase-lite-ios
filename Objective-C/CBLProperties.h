//
//  CBLProperties.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLSubdocument;

/** CBLProperties defines interface for document and subdocument property type accessors. */
@protocol CBLProperties <NSObject>

NS_ASSUME_NONNULL_BEGIN

/** The content of the document or subdocument. */
@property (readwrite, nullable, nonatomic) NSDictionary* properties;

#pragma mark - GETTERS

/** Get a boolean value by key. Returns NO if the property doesn't exist. */
- (BOOL) booleanForKey: (NSString*)key;

/** Get an NSDate object by key. The NSDate object is converted from an ISO-8601 date
    formatted string. Return nil if the property doesn't exists. */
- (nullable NSDate*) dateForKey: (NSString*)key;

/** Get a double value by key. Returns 0.0 if the property doesn't exists. */
- (double) doubleForKey: (NSString*)key;

/** Get a float value by key. Returns 0.0 if the property doesn't exists. */
- (float) floatForKey: (NSString*)key;

/** Get an integer value by key. Returns 0 if the property doesn't exists. */
- (NSInteger) integerForKey: (NSString*)key;

/** Get an object by key. The returned object could be one of these types NSNumber,
    NSString, NSArray, and CBLSubdocument based on the underlining data type. The 
    CBLSubdocument object is basically mapped to an NSDictionary to provide 
    property type accessors. Return nil if the property doesn't exists. */
- (nullable id) objectForKey: (NSString*)key;

/** Get an NSString property by key. Returns nil if the property doesn't exists. */
- (nullable NSString*) stringForKey: (NSString*)key;

/** Get or create a new CBLSubdocument by key. */
- (CBLSubdocument*) subdocumentForKey: (NSString*)key;

#pragma mark - SETTERS

/** Set a boolean value by key. */
- (void) setBoolean: (BOOL)value forKey: (NSString*)key;

/** Set a double value by key. */
- (void) setDouble: (double)value forKey: (NSString*)key;

/** Set a float value by key. */
- (void) setFloat: (float)value forKey: (NSString*)key;

/** Set an integer value by key. */
- (void) setInteger: (NSInteger)value forKey: (NSString*)key;

/** Set an object by key. Setting nil value will remove the property. */
- (void) setObject: (nullable id)value forKey: (NSString*)key;

#pragma mark - SUBSCRIPTION

/** Same as objectForKey: */
- (nullable id) objectForKeyedSubscript: (NSString*)key;

/** Same as setObject:forKey: */
- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key;

#pragma mark - OTHERS

/** Remove a property by key. */
- (void) removeObjectForKey: (NSString*)key;

/** Check whether a property exists or not by key. */
- (BOOL) containsObjectForKey: (NSString*)key;

@end

/** Super class for CBLDocument and CBLSubdocument that implements CBLProperties protocol to
 provide property accessors. */
@interface CBLProperties: NSObject <CBLProperties>
@end

NS_ASSUME_NONNULL_END

// TODO:
// 1. Evaluate get/set Array of a specific type (new API)
// 2. Subdocument (In progress)
// 3. Blob (Need design)
// 4. Property complex object (Can be deferred)
// 5. Iterable or ObjC Equivalent (Can be deferred)
