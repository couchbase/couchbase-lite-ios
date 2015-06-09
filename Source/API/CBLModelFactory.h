//
//  CBLModelFactory.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/22/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase.h"
@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN

/** A configurable mapping from CBLDocument to CBLModel.
    It associates a model class with a value of the document's "type" property. */
@interface CBLModelFactory : NSObject

/** Returns a global shared CBLModelFactory that's consulted by all databases.
    Mappings registered in this instance will be used as a fallback by all other instances if they don't have their own. */
+ (instancetype) sharedInstance;

/** Given a document, attempts to return a CBLModel for it.
    If the document's modelObject property is set, it returns that value.
    If the document's "type" property has been registered, instantiates the associated class.
    Otherwise returns nil. */
- (id) modelForDocument: (CBLDocument*)document;

/** Associates a value of the "type" property with a CBLModel subclass.
    When a document with this type value is loaded as a model, the given subclass will be
    instantiated (unless you explicitly instantiate a different CBLModel subclass.)
    As a bonus, when a model of this class is created with a new document, the document's "type"
    property will be set to the associated value.
    @param classOrName  Either a CBLModel subclass, or its class name as an NSString.
    @param type  The value value of a document's "type" property that should indicate this class. */
- (void) registerClass: (id)classOrName
       forDocumentType: (NSString*)type;

/** Returns the appropriate CBLModel subclass for this document.
    The default implementation just passes the document's "type" property value to -classForDocumentType:, but subclasses could override this to use different properties (or even the document ID) to decide. */
- (nullable Class) classForDocument: (CBLDocument*)document;

/** Looks up the CBLModel subclass that's been registered for a document type. */
- (Class) classForDocumentType: (NSString*)type;

/** Looks up the document type for which the given class has been registered.
    If it's unregistered, or registered with multiple types, returns nil. */
- (nullable NSString*) documentTypeForClass: (Class)modelClass;

/** Looks up the document types for which the given class has been registered. */
- (CBLArrayOf(NSString*)*) documentTypesForClass: (Class)modelClass;

@end


@interface CBLDatabase (CBLModelFactory)

/** The CBLModel factory object to be used by this database.
    Every database has its own instance by default, but you can set this property to use a different one -- either to use a custom subclass, or to share a factory among multiple databases, or both. */
@property (retain, nullable) CBLModelFactory* modelFactory;

@end


NS_ASSUME_NONNULL_END
