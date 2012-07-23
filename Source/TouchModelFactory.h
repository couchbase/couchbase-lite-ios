//
//  TouchModelFactory.h
//  TouchDB
//
//  Created by Jens Alfke on 11/22/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TouchDatabase.h"
@class TouchDocument;


/** A configurable mapping from TouchDocument to TouchModel.
    It associates a model class with a value of the document's "type" property. */
@interface TouchModelFactory : NSObject
{
    NSMutableDictionary* _typeDict;
}

/** Returns a global shared TouchModelFactory that's consulted by all databases.
    Mappings registered in this instance will be used as a fallback by all other instances if they don't have their own. */
+ (TouchModelFactory*) sharedInstance;

/** Given a document, attempts to return a TouchModel for it.
    If the document's modelObject property is set, it returns that value.
    If the document's "type" property has been registered, instantiates the associated class.
    Otherwise returns nil. */
- (id) modelForDocument: (TouchDocument*)document;

/** Associates a value of the "type" property with a TouchModel subclass.
    @param classOrName  Either a TouchModel subclass, or its class name as an NSString.
    @param type  The value value of a document's "type" property that should indicate this class. */
- (void) registerClass: (id)classOrName forDocumentType: (NSString*)type;

/** Returns the appropriate TouchModel subclass for this document.
    The default implementation just passes the document's "type" property value to -classForDocumentType:, but subclasses could override this to use different properties (or even the document ID) to decide. */
- (Class) classForDocument: (TouchDocument*)document;

/** Looks up the TouchModel subclass that's been registered for a document type. */
- (Class) classForDocumentType: (NSString*)type;

@end


@interface TouchDatabase (TouchModelFactory)

/** The TouchModel factory object to be used by this database.
    Every database has its own instance by default, but you can set this property to use a different one -- either to use a custom subclass, or to share a factory among multiple databases, or both. */
@property (retain) TouchModelFactory* modelFactory;
@end