//
//  CBLQueryParameters.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryParameters : NSObject

/**
 Set the value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The object.
 @pram name The parameter name.
 */
- (void) setValue: (nullable id)value forName: (NSString*)name;

/**
 Set the String value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The String value.
 @pram name The parameter name.
 */
- (void) setString: (nullable NSString*)value forName: (NSString*)name;

/**
 Set the NSNumber value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The NSNumber value.
 @pram name The parameter name.
 */
- (void) setNumber: (nullable NSNumber*)value forName: (NSString*)name;

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
 Set the float value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The float value.
 @pram name The parameter name.
 */
- (void) setFloat: (float)value forName: (NSString*)name;

/**
 Set the double value to the query parameter referenced by the given name. A query parameter
 is defined by using the CBLQueryExpression's + parameterNamed: method.
 
 @param value The double value.
 @pram name The parameter name.
 */
- (void) setDouble: (double)value forName: (NSString*)name;

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
 Get the parameter value.
 
 @param name The name of the parameter.
 @return The value of the parameter.
 */
- (nullable id) valueForName: (NSString*)name;

/**
 Initializes the CBLQueryParameters object.
 */
- (instancetype) init;

/**
 Initializes the CBLQueryParameters object with the parameters object.
 */
- (instancetype) initWithParameters: (nullable CBLQueryParameters*)parameters;

@end

NS_ASSUME_NONNULL_END

