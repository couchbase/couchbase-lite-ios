//
//  CBLQueryParameters.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** 
 A CBLQueryParameters object used for setting values to the query parameters defined
 in the query.
 */
@interface CBLQueryParameters : NSObject

/** 
 Set the boolean value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The boolean value.
 @pram name The parameter name.
 */
- (void) setBoolean: (BOOL)value forName: (NSString*)name;

/** 
 Set the NSDate object to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The NSDate value.
 @pram name The parameter name.
 */
- (void) setDate: (nullable NSDate*)value forName: (NSString*)name;

/** 
 Set the double value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The double value.
 @pram name The parameter name.
 */
- (void) setDouble: (double)value forName: (NSString*)name;

/** 
 Set the float value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The float value.
 @pram name The parameter name.
 */
- (void) setFloat: (float)value forName: (NSString*)name;

/** 
 Set the integer value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The integer value.
 @pram name The parameter name.
 */
- (void) setInteger: (NSInteger)value forName: (NSString*)name;

/**
 Set the long long value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The long long value.
 @pram name The parameter name.
 */
- (void) setLongLong: (long long)value forName: (NSString*)name;

/** 
 Set the NSNumber value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The NSNumber value.
 @pram name The parameter name.
 */
- (void) setNumber: (nullable NSNumber*)value forName: (NSString*)name;

/** 
 Set the value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The object.
 @pram name The parameter name.
 */
- (void) setObject: (nullable id)value forName: (NSString*)name;

/** 
 Set the String value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The String value.
 @pram name The parameter name.
 */
- (void) setString: (nullable NSString*)value forName: (NSString*)name;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

