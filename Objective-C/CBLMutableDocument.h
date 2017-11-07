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
 Initializes a new CBLMutableDocument object with a new random UUID and the dictionary as the content.
 Allowed dictionary value types are NSArray, NSDate, NSDictionary, NSNumber, NSNull, NSString,
 CBLMutableArray, CBLBlob, CBLMutableDictionary. The NSArrays and NSDictionaries must contain only
 the above types. The created document will be saved into a database when you call the
 CBLDatabase's -save: method with the document object given.
 
 @param dictionary The dictionary object.
 */
- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary;

/** 
 Initializes a new CBLMutableDocument object with a given ID and the dictionary as the content. If a
 nil ID value is given, the document will be created with a new random UUID.
 Allowed dictionary value types are NSArray, NSDate, NSDictionary, NSNumber, NSNull, NSString,
 CBLMutableArray, CBLBlob, CBLMutableDictionary. The NSArrays and NSDictionaries must contain only
 the above types. The created document will be saved into a database when you call the
 CBLDatabase's -save: method with the document object given.
 
 @param documentID The document ID.
 @param dictionary The dictionary object.
 */
- (instancetype) initWithID: (nullable NSString*)documentID
                 dictionary: (NSDictionary<NSString*,id>*)dictionary;

@end

NS_ASSUME_NONNULL_END
