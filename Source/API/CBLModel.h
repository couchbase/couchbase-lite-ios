//
//  CBLModel.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/26/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "MYDynamicObject.h"
#import "CBLDocument.h"
@class CBLAttachment, CBLDatabase, CBLDocument;


NS_REQUIRES_PROPERTY_DEFINITIONS  // Don't let compiler auto-synthesize properties in subclasses
/** Generic model class for CouchbaseLite documents.
    There's a 1::1 mapping between these and CBLDocuments; call +modelForDocument: to get (or create) a model object for a document, and .document to get the document of a model.
    You should subclass this and declare properties in the subclass's @@interface. As with NSManagedObject, you don't need to implement their accessor methods or declare instance variables; simply note them as '@@dynamic' in the class @@implementation. The property value will automatically be fetched from or stored to the document, using the same name.
    Supported scalar types are bool, char, short, int, double. These map to JSON numbers, except 'bool' which maps to JSON 'true' and 'false'. (Use bool instead of BOOL.)
    Supported object types are NSString, NSNumber, NSData, NSDate, NSArray, NSDictionary, NSDecimalNumber. (NSData and NSDate are not native JSON; they will be automatically converted to/from strings in base64 and ISO date formats, respectively. NSDecimalNumber is not native JSON as well; it will be converted to/from string.)
    Additionally, a property's type can be a pointer to a CBLModel subclass. This provides references between model objects. The raw property value in the document must be a string whose value is interpreted as a document ID.
    NSArray-valued properties may be restricted to a specific item class. See the documentation of +itemClassForArrayProperty: for details. */
@interface CBLModel : MYDynamicObject <CBLDocumentModel>

/** Returns the CBLModel associated with a CBLDocument, or creates & assigns one if necessary.
    If the CBLDocument already has an associated model, it's returned. Otherwise a new one is instantiated.
    If you call this on CBLModel itself, it'll delegate to the CBLModelFactory to decide what class to instantiate; this lets you map different classes to different "type" property values, for instance.
    If you call this method on a CBLModel subclass, it will always instantiate an instance of that class; e.g. [MyWidgetModel modelForDocument: doc] always creates a MyWidgetModel. */
+ (instancetype) modelForDocument: (CBLDocument*)document               __attribute__((nonnull));

/** Creates a new "untitled" model with a new unsaved document.
    The document won't be written to the database until -save is called. */
- (instancetype) initWithNewDocumentInDatabase: (CBLDatabase*)database  __attribute__((nonnull));

/** Creates a new "untitled" model object with no document or database at all yet.
    Setting its .database property will cause it to create a CBLDocument.
    (This method is mostly here so that NSController objects can create CBLModels.) */
- (instancetype) init;

/** The document this item is associated with. Will be nil if it's new and unsaved. */
@property (readonly, retain) CBLDocument* document;

/** The database the item's document belongs to.
    Setting this property will assign the item to a database, creating a document.
    Setting it to nil will delete its document from its database. */
@property (retain) CBLDatabase* database;

/** Is this model new, never before saved? */
@property (readonly) bool isNew;

#pragma mark - SAVING:

/** Writes any changes to a new revision of the document.
    Returns YES without doing anything, if no changes have been made. */
- (BOOL) save: (NSError**)outError;

/** Should changes be saved back to the database automatically?
    Defaults to NO, requiring you to call -save manually. */
@property (nonatomic) bool autosaves;

/** How long to wait after the first change before auto-saving, if autosaves is true.
    Default value is 0.0; subclasses can override this to add a delay. */
@property (readonly) NSTimeInterval autosaveDelay;

/** Does this model have unsaved changes? */
@property (readonly) bool needsSave;

/** The document's current properties (including unsaved changes) in externalized JSON format.
    This is what will be written to the CBLDocument when the model is saved. */
- (NSDictionary*) propertiesToSave;

/** Removes any changes made to properties and attachments since the last save. */
- (void) revertChanges;

/** Deletes the document from the database. 
    You can still use the model object afterwards, but it will refer to the deleted revision. */
- (BOOL) deleteDocument: (NSError**)outError;

/** The time interval since the document was last changed externally (e.g. by a "pull" replication.
    This value can be used to highlight recently-changed objects in the UI. */
@property (readonly) NSTimeInterval timeSinceExternallyChanged;

/** Bulk-saves changes to multiple model objects (which must all be in the same database).
    The saves are performed in one transaction, for efficiency.
    Any unchanged models in the array are ignored.
    See also: -[CBLDatabase saveAllModels:].
    @param models  An array of CBLModel objects, which must all be in the same database.
    @param outError  On return, the error (if the call failed.)
    @return  A RESTOperation that saves all changes, or nil if none of the models need saving. */
+ (BOOL) saveModels: (NSArray*)models
              error: (NSError**)outError;

/** Resets the timeSinceExternallyChanged property to zero. */
- (void) markExternallyChanged;

#pragma mark - PROPERTIES & ATTACHMENTS:

/** Gets a property by name.
    You can use this for document properties that you haven't added @@property declarations for. */
- (id) getValueOfProperty: (NSString*)property                          __attribute__((nonnull));

/** Sets a property by name.
    You can use this for document properties that you haven't added @@property declarations for. */
- (BOOL) setValue: (id)value
       ofProperty: (NSString*)property                                  __attribute__((nonnull(2)));


/** The names of all attachments (array of strings).
    This reflects unsaved changes made by creating or deleting attachments. */
@property (readonly) NSArray* attachmentNames;

/** Looks up the attachment with the given name (without fetching its contents). */
- (CBLAttachment*) attachmentNamed: (NSString*)name                     __attribute__((nonnull));

/** Creates, updates or deletes an attachment.
    The attachment data will be written to the database when the model is saved.
    @param name  The attachment name. By convention, this looks like a filename.
    @param mimeType  The MIME type of the content.
    @param content  The body of the attachment. If this is nil, any existing attachment with this
                    name will be deleted. */
- (void) setAttachmentNamed: (NSString*)name
            withContentType: (NSString*)mimeType
                    content: (NSData*)content                           __attribute__((nonnull));

/** Creates, updates or deletes an attachment whose body comes from a file.
    (The method takes a URL, but it must be a "file:" URL. Remote resources are not supported.)
    The file need only be readable. It won't be moved or altered in any way.
    The attachment data will be copied from the file into the database when the model is saved.
    The file needs to be preserved until then, but afterwards it can safely be deleted.
    @param name  The attachment name. By convention, this looks like a filename.
    @param mimeType  The MIME type of the content.
    @param fileURL  The URL of a local file whose contents should be copied into the attachment.
                     If this is nil, any existing attachment with this name will be deleted.*/
- (void) setAttachmentNamed: (NSString*)name
            withContentType: (NSString*)mimeType
                 contentURL: (NSURL*)fileURL                            __attribute__((nonnull));

/** Deletes (in memory) any existing attachment with the given name.
    The attachment will be deleted from the database at the same time as property changes are saved. */
- (void) removeAttachmentNamed: (NSString*)name                         __attribute__((nonnull));


#pragma mark - PROTECTED (FOR SUBCLASSES TO OVERRIDE)

/** Designated initializer. Do not call directly except from subclass initializers; to create a new instance call +modelForDocument: instead.
    @param document  The document. Nil if this is created new (-init was called). */
- (instancetype) initWithDocument: (CBLDocument*)document
#ifdef NS_DESIGNATED_INITIALIZER
NS_DESIGNATED_INITIALIZER
#endif
;

/** The document ID to use when creating a new document.
    Default is nil, which means to assign no ID (the server will assign one). */
- (NSString*) idForNewDocumentInDatabase: (CBLDatabase*)db              __attribute__((nonnull));

/** Called when the model's properties are reloaded from the document.
    This happens both when initialized from a document, and after an external change. */
- (void) didLoadFromDocument;

/** Returns the database in which to look up the document ID of a model-valued property.
    Defaults to the same database as the receiver's document. You should override this if a document property contains the ID of a document in a different database. */
- (CBLDatabase*) databaseForModelProperty: (NSString*)propertyName      __attribute__((nonnull));

/** Marks the model as having unsaved content, ensuring that it will get saved after a short interval (if .autosaves is YES) or when -save or -[CBLDatabase saveAllModels] are called.
    You don't normally need to call this, since property setters call it for you. One case where you'd need to call it is if you want to manage mutable state in your own properties and not store the changes into dynamic properties until it's time to save. In that case you should also override -propertiesToSave and update the dynamic properties accordingly before chaining to the superclass method. */
- (void) markNeedsSave;

/** Called while saving a document, before building the new revision's dictionary.
    This method can modify property values if it wants to. */
- (void) willSave: (NSSet*)changedPropertyNames;

/** If you want properties to be saved in the document when it's deleted (in addition to the required "_deleted":true) override this method to return those properties.
    This is called by -deleteDocument:. The default implementation returns {"_deleted":true}. */
- (NSDictionary*) propertiesToSaveForDeletion;

/** General method for declaring the class of items in a property of type NSArray*.
    Given the property name, the override should return a class that all items must inherit from,
    or nil if the property is untyped. Supported classes are CBLModel (or any subclass),
    NSData, NSDate, NSDecimalNumber, and any JSON-compatible class (NSNumber, NSString, etc.)
    If you don't recognize the property name you should call the superclass method.
 
    The default implementation of this method checks for the existence of a class method with
    selector of the form +propertyItemClass where 'property' is replaced by the actual property
    name. If such a method exists it is called, and must return a class.
 
    In general you'll find it easier to implement the '+propertyItemClass' method(s) rather
    than overriding this one. */
+ (Class) itemClassForArrayProperty: (NSString*)property;

/** The type of document. This is optional, but is commonly used in document databases 
    to distinguish different types of documents. CBLModelFactory can use this property to 
    determine what CBLModel subclass to instantiate for a document. */
@property (copy, nonatomic) NSString* type;

@end



/** CBLDatabase methods for use with CBLModel. */
@interface CBLDatabase (CBLModel)

/** All CBLModels associated with this database whose needsSave is true. */
@property (readonly) NSArray* unsavedModels;

/** Saves changes to all CBLModels associated with this database whose needsSave is true. */
- (BOOL) saveAllModels: (NSError**)outError;

/** Immediately runs any pending autosaves for all CBLModels associated with this database.
    (On iOS, this will automatically be called when the application is about to quit or go into the
    background. On Mac OS it is NOT called automatically.) */
- (BOOL) autosaveAllModels: (NSError**)outError;

@end
