//
//  CBLModelFactory.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/22/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase.h"
@class CBLDocument;


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
- (id) modelForDocument: (CBLDocument*)document                         __attribute__((nonnull));

/** Associates a value of the "type" property with a CBLModel subclass.
    @param classOrName  Either a CBLModel subclass, or its class name as an NSString.
    @param type  The value value of a document's "type" property that should indicate this class. */
- (void) registerClass: (id)classOrName
       forDocumentType: (NSString*)type                                 __attribute__((nonnull(2)));

/** Returns the appropriate CBLModel subclass for this document.
    The default implementation just passes the document's "type" property value to -classForDocumentType:, but subclasses could override this to use different properties (or even the document ID) to decide. */
- (Class) classForDocument: (CBLDocument*)document                      __attribute__((nonnull));

/** Looks up the CBLModel subclass that's been registered for a document type. */
- (Class) classForDocumentType: (NSString*)type                         __attribute__((nonnull));

@end


@interface CBLDatabase (CBLModelFactory)

/** The CBLModel factory object to be used by this database.
    Every database has its own instance by default, but you can set this property to use a different one -- either to use a custom subclass, or to share a factory among multiple databases, or both. */
@property (retain) CBLModelFactory* modelFactory;

@end
