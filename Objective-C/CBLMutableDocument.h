//
//  CBLMutableDocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
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
