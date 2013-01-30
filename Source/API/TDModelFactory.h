//
//  TDModelFactory.h
//  TouchDB
//
//  Created by Jens Alfke on 11/22/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
@class TDDocument;


/** A configurable mapping from TDDocument to TDModel.
    It associates a model class with a value of the document's "type" property. */
@interface TDModelFactory : NSObject

/** Returns a global shared TDModelFactory that's consulted by all databases.
    Mappings registered in this instance will be used as a fallback by all other instances if they don't have their own. */
+ (TDModelFactory*) sharedInstance;

/** Given a document, attempts to return a TDModel for it.
    If the document's modelObject property is set, it returns that value.
    If the document's "type" property has been registered, instantiates the associated class.
    Otherwise returns nil. */
- (id) modelForDocument: (TDDocument*)document;

/** Associates a value of the "type" property with a TDModel subclass.
    @param classOrName  Either a TDModel subclass, or its class name as an NSString.
    @param type  The value value of a document's "type" property that should indicate this class. */
- (void) registerClass: (id)classOrName forDocumentType: (NSString*)type;

/** Returns the appropriate TDModel subclass for this document.
    The default implementation just passes the document's "type" property value to -classForDocumentType:, but subclasses could override this to use different properties (or even the document ID) to decide. */
- (Class) classForDocument: (TDDocument*)document;

/** Looks up the TDModel subclass that's been registered for a document type. */
- (Class) classForDocumentType: (NSString*)type;

@end


@interface TDDatabase (TDModelFactory)

/** The TDModel factory object to be used by this database.
    Every database has its own instance by default, but you can set this property to use a different one -- either to use a custom subclass, or to share a factory among multiple databases, or both. */
@property (retain) TDModelFactory* modelFactory;

@end
