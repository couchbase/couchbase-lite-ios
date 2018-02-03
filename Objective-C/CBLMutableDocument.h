//
//  CBLMutableDocument.h
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
#import "CBLDocument.h"
#import "CBLMutableDictionary.h"
@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

/** The mutable version of the CBLDocument. */
@interface CBLMutableDocument : CBLDocument <CBLMutableDictionary>

/** 
 Creates a new CBLMutableDocument object with a new random UUID. The created document will be
 saved into a database when you call the CBLDatabase's -save: method with the document
 object given.
 */
+ (instancetype) document;

/** 
 Creates a new CBLMutableDocument object with the given ID. If a nil ID value is given, the document
 will be created with a new random UUID. The created document will be saved into a database
 when you call the CBLDatabase's -save: method with the document object given.
 
 @param documentID The document ID.
 */
+ (instancetype) documentWithID: (nullable NSString*)documentID;

/** 
 Initializes a new CBLMutableDocument object with a new random UUID. The created document will be
 saved into a database when you call the CBLDatabase's -save: method with the document
 object given.
 */
- (instancetype) init;

/** 
 Initializes a new CBLMutableDocument object with the given ID. If a nil ID value is given, the document
 will be created with a new random UUID. The created document will be saved into a database when
 you call the CBLDatabase's -save: method with the document object given.
 
 @param documentID The document ID.
 */
- (instancetype) initWithID: (nullable NSString*)documentID;

/** 
 Initializes a new CBLMutableDocument object with a new random UUID and the data.
 Allowed data value types are CBLArray, CBLBlob, CBLDictionary, NSArray,
 NSDate, NSDictionary, NSNumber, NSNull, NSString. The NSArrays and NSDictionaries
 must contain only the above types. The created document will be saved into a
 database when you call the CBLDatabase's -save: method with the document
 object given.
 
 @param data The data.
 */
- (instancetype) initWithData: (nullable NSDictionary<NSString*,id>*)data;

/** 
 Initializes a new CBLMutableDocument object with the given ID and the data. If a
 nil ID value is given, the document will be created with a new random UUID.
 Allowed data value types are CBLMutableArray, CBLBlob, CBLMutableDictionary, NSArray,
 NSDate, NSDictionary, NSNumber, NSNull, NSString. The NSArrays and NSDictionaries
 must contain only the above types. The created document will be saved into a
 database when you call the CBLDatabase's -save: method with the document
 object given.
 
 @param documentID The document ID.
 @param data The data.
 */
- (instancetype) initWithID: (nullable NSString*)documentID
                       data: (nullable NSDictionary<NSString*,id>*)data;

@end

NS_ASSUME_NONNULL_END
