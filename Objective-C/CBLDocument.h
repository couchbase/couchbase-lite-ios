//
//  CBLDocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyDocument.h"
#import "CBLDictionary.h"
@class CBLDatabase;
@protocol CBLConflictResolver;

NS_ASSUME_NONNULL_BEGIN

/** A Couchbase Lite document.
    A document has key/value properties like an NSDictionary; their API is defined by the
    protocol CBLProperties. To learn how to work with properties, see that protocol's
    documentation. */
@interface CBLDocument : CBLReadOnlyDocument <CBLDictionary>

/** Creates a new CBLDocument object with a new random UUID. The created document will be
    saved into a database when you call the CBLDatabase's -save: method with the document 
    object given.
    @result the CBLDocument object. */
+ (instancetype) document;

/** Creates a new CBLDocument object with the given ID. If a nil ID value is given, the document
    will be created with a new random UUID. The created document will be saved into a database 
    when you call the CBLDatabase's -save: method with the document  object given.
    @param documentID   the document ID.
    @result the CBLDocument object. */
+ (instancetype) documentWithID: (nullable NSString*)documentID;

/** Initializes a new CBLDocument object with a new random UUID. The created document will be
    saved into a database when you call the CBLDatabase's -save: method with the document 
    object given.
    @result the CBLDocument object. */
- (instancetype) init;

/** Initializes a new CBLDocument object with the given ID. If a nil ID value is given, the document
    will be created with a new random UUID. The created document will be saved into a database when 
    you call the CBLDatabase's -save: method with the document object
    given.
    @param documentID   the document ID.
    @result the CBLDocument object. */
- (instancetype) initWithID: (nullable NSString*)documentID;

/** Initializes a new CBLDocument object with a new random UUID and the dictionary as the content.
    Allowed dictionary value types are NSArray, NSDate, NSDictionary, NSNumber, NSNull, NSString,
    CBLArray, CBLBlob, CBLDictionary. The NSArrays and NSDictionaries must contain only
    the above types. The created document will be saved into a database when you call the 
    CBLDatabase's -save: method with the document object given.
    @param dictionary   the dictionary object.
    @result the CBLDocument object. */
- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary;

/** Initializes a new CBLDocument object with a given ID and the dictionary as the content. If a 
    nil ID value is given, the document will be created with a new random UUID.
    Allowed dictionary value types are NSArray, NSDate, NSDictionary, NSNumber, NSNull, NSString,
    CBLArray, CBLBlob, CBLDictionary. The NSArrays and NSDictionaries must contain only
    the above types. The created document will be saved into a database when you call the
    CBLDatabase's -save: method with the document object given.
    @param documentID   the document ID.
    @param dictionary   the dictionary object.
    @result the CBLDocument object. */
- (instancetype) initWithID: (nullable NSString*)documentID
                 dictionary: (NSDictionary<NSString*,id>*)dictionary;

@end

NS_ASSUME_NONNULL_END
