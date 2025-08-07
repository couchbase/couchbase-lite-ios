//
//  CBLPrecondition.h
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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

@interface CBLPrecondition : NSObject

/** Asserts that the specified condition is true */
+ (void) assert: (BOOL)condition message: (NSString*)message;

/** Asserts that the specified condition is true */
+ (void) assert: (BOOL)condition format: (NSString*)format, ... NS_FORMAT_FUNCTION(2,3);

/** Asserts that the specified object is not nil. */
+ (void) assertNotNil: (nullable id)object name: (NSString*)name;

/** Asserts that the specified array is not nil and not empty. */
+ (void) assertArrayNotEmpty: (nullable NSArray*)array name: (NSString*)name;

@end

NS_ASSUME_NONNULL_END
