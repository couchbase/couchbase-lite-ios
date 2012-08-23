//
//  TouchModel.m
//  TouchDB
//
//  Created by Jens Alfke on 8/26/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TouchModel.h"
#import "TouchModelFactory.h"
#import "TouchDBPrivate.h"
#import "TDMisc.h"
#import "TDBase64.h"
#import <objc/runtime.h>


@interface TouchModel ()
@property (readwrite, retain) TouchDocument* document;
@property (readwrite) bool needsSave;
@end


@implementation TouchModel


- (id)init {
    return [self initWithDocument: nil];
}

- (id) initWithDocument: (TouchDocument*)document
{
    self = [super init];
    if (self) {
        if (document) {
            LogTo(TouchModel, @"%@ initWithDocument: %@ @%p", self, document, document);
            self.document = document;
            [self didLoadFromDocument];
        } else {
            _isNew = true;
            LogTo(TouchModel, @"%@ init", self);
        }
    }
    return self;
}


- (id) initWithNewDocumentInDatabase: (TouchDatabase*)database {
    NSParameterAssert(database);
    self = [self initWithDocument: nil];
    if (self) {
        self.database = database;
    }
    return self;
}


+ (id) modelForDocument: (TouchDocument*)document {
    NSParameterAssert(document);
    TouchModel* model = document.modelObject;
    if (model) {
        // Document already has a model; make sure it's type-compatible with the desired class
        NSAssert([model isKindOfClass: self], @"%@: %@ already has incompatible model %@",
                 self, document, model);
    } else if (self != [TouchModel class]) {
        // If invoked on a subclass of TouchModel, create an instance of that subclass:
        model = [[[self alloc] initWithDocument: document] autorelease];
    } else {
        // If invoked on TouchModel itself, ask the factory to instantiate the appropriate class:
        model = [document.database.modelFactory modelForDocument: document];
        if (!model)
            Warn(@"Couldn't figure out what model class to use for doc %@", document);
    }
    return model;
}


- (void) dealloc
{
    LogTo(TouchModel, @"%@ dealloc", self);
    _document.modelObject = nil;
    [_document release];
    [_properties release];
    [_changedNames release];
    [_changedAttachments release];
    [super dealloc];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]",
                self.class, TDAbbreviate(self.document.documentID)];
}


#pragma mark - DOCUMENT / DATABASE:


- (TouchDocument*) document {
    return _document;
}


- (void) setDocument:(TouchDocument *)document {
    NSAssert(!_document && document, @"Can't change or clear document");
    NSAssert(document.modelObject == nil, @"Document already has a model");
    _document = [document retain];
    _document.modelObject = self;
}


- (void) detachFromDocument {
    _document.modelObject = nil;
    [_document release];
    _document = nil;
}


- (NSString*) idForNewDocumentInDatabase: (TouchDatabase*)db {
    return nil;  // subclasses can override this to customize the doc ID
}


- (TouchDatabase*) database {
    return _document.database;
}


- (void) setDatabase: (TouchDatabase*)db {
    if (db) {
        // On setting database, create a new untitled/unsaved TouchDocument:
        NSString* docID = [self idForNewDocumentInDatabase: db];
        self.document = docID ? [db documentWithID: docID] : [db untitledDocument];
        LogTo(TouchModel, @"%@ made new document", self);
    } else {
        [self deleteDocument: nil];
        [self detachFromDocument];  // detach immediately w/o waiting for success
    }
}


- (BOOL) deleteDocument: (NSError**)outError {
    TouchRevision* rev = _document.currentRevision;
    if (!rev)
        return YES;
    LogTo(TouchModel, @"%@ Deleting document", self);
    _needsSave = NO;        // prevent any pending saves
    rev = [rev deleteDocument: outError];
    if (!rev)
        return NO;
    [self detachFromDocument];
    return YES;
}


- (void) didLoadFromDocument {
    // subclasses can override this
}


// Respond to an external change (likely from sync). This is called by my TouchDocument.
- (void) couchDocumentChanged: (TouchDocument*)doc {
    NSAssert(doc == _document, @"Notified for wrong document");
    LogTo(TouchModel, @"%@ External change (rev=%@)", self, _document.currentRevisionID);
    [self markExternallyChanged];
    
    // Send KVO notifications about all my properties in case they changed:
    NSSet* keys = [[self class] propertyNames];
    for (NSString* key in keys)
        [self willChangeValueForKey: key];
    
    // Remove unchanged cached values in _properties:
    if (_changedNames && _properties) {
        NSMutableSet* removeKeys = [NSMutableSet setWithArray: [_properties allKeys]];
        [removeKeys minusSet: _changedNames];
        [_properties removeObjectsForKeys: removeKeys.allObjects];
    } else {
        [_properties release];
        _properties = nil;
    }
    
    [self didLoadFromDocument];
    for (NSString* key in keys)
        [self didChangeValueForKey: key];
}


- (NSTimeInterval) timeSinceExternallyChanged {
    return CFAbsoluteTimeGetCurrent() - _changedTime;
}

- (void) markExternallyChanged {
    _changedTime = CFAbsoluteTimeGetCurrent();
}


#pragma mark - SAVING:


@synthesize isNew=_isNew, autosaves=_autosaves, needsSave=_needsSave;


- (void) setAutosaves: (bool) autosaves {
    if (autosaves != _autosaves) {
        _autosaves = autosaves;
        if (_autosaves && _needsSave)
            [self performSelector: @selector(save:) withObject: nil afterDelay: 0.0];
    }
}


- (void) markNeedsSave {
    if (_autosaves && !_needsSave)
        [self performSelector: @selector(save:) withObject: nil afterDelay: 0.0];
    self.needsSave = YES;
}


- (void) didSave {
    if (!_needsSave || (!_changedNames && !_changedAttachments))
        return;
    self.needsSave = NO;
    _isNew = NO;
    [_properties release];
    _properties = nil;
    [_changedNames release];
    _changedNames = nil;
    [_changedAttachments release];
    _changedAttachments = nil;
}


- (BOOL) save: (NSError**)outError {
    if (!_needsSave || (!_changedNames && !_changedAttachments))
        return YES;
    NSDictionary* properties = self.propertiesToSave;
    LogTo(TouchModel, @"%@ Saving <- %@", self, properties);
    NSError* error;
    if (![_document putProperties: properties error: &error]) {
        if (outError)
            *outError = error;
        else
            Warn(@"%@: Save failed: %@", self, error);
        return NO;
    }
    [self didSave];
    return YES;
}


+ (BOOL) saveModels: (NSArray*)models error: (NSError**)outError {
    if (models.count == 0)
        return YES;
    TouchDatabase* db = [[models objectAtIndex: 0] database];
    BOOL saved = [db inTransaction: ^{
        for (TouchModel* model in models) {
            NSAssert(model.database == db, @"Models must share a common db");
            if (![model save: outError])
                return NO;
        }
        return YES;
    }];
    if (saved)
        for (TouchModel* model in models)
            [model didSave];
    return saved;
}


#pragma mark - PROPERTIES:


- (NSDictionary*) currentProperties {
    NSMutableDictionary* properties = [_document.properties mutableCopy];
    if (!properties)
        properties = [[NSMutableDictionary alloc] init];
    for (NSString* key in _changedNames)
        [properties setValue: [_properties objectForKey: key] forKey: key];
    return [properties autorelease];
}


+ (NSSet*) propertyNames {
    if (self == [TouchModel class])
        return [NSSet set]; // Ignore non-persisted properties declared on base TouchModel
    return [super propertyNames];
}

// Transforms cached property values back into JSON-compatible objects
- (id) externalizePropertyValue: (id)value {
    if ([value isKindOfClass: [NSData class]])
        value = [TDBase64 encode: value];
    else if ([value isKindOfClass: [NSDate class]])
        value = [TDJSON JSONObjectWithDate: value];
    return value;
}


- (NSDictionary*) propertiesToSave {
    NSMutableDictionary* properties = [_document.properties mutableCopy];
    if (!properties)
        properties = [[NSMutableDictionary alloc] init];
    for (NSString* key in _changedNames) {
        id value = [_properties objectForKey: key];
        [properties setValue: [self externalizePropertyValue: value] forKey: key];
    }
    [properties setValue: self.attachmentDataToSave forKey: @"_attachments"];
    return [properties autorelease];
}


- (void) cacheValue: (id)value ofProperty: (NSString*)property changed: (BOOL)changed {
    if (!_properties)
        _properties = [[NSMutableDictionary alloc] init];
    [_properties setValue: value forKey: property];
    if (changed) {
        if (!_changedNames)
            _changedNames = [[NSMutableSet alloc] init];
        [_changedNames addObject: property];
    }
}


- (id) getValueOfProperty: (NSString*)property {
    id value = [_properties objectForKey: property];
    if (!value && ![_changedNames containsObject: property]) {
        value = [_document propertyForKey: property];
    }
    return value;
}


- (BOOL) setValue: (id)value ofProperty: (NSString*)property {
    NSParameterAssert(_document);
    id curValue = [self getValueOfProperty: property];
    if (!$equal(value, curValue)) {
        LogTo(TouchModel, @"%@ .%@ := \"%@\"", self, property, value);
        [self cacheValue: value ofProperty: property changed: YES];
        [self markNeedsSave];
    }
    return YES;
}


#pragma mark - PROPERTY TRANSFORMATIONS:


- (NSData*) getDataProperty: (NSString*)property {
    NSData* value = [_properties objectForKey: property];
    if (!value) {
        id rawValue = [_document propertyForKey: property];
        if ([rawValue isKindOfClass: [NSString class]])
            value = [TDBase64 decode: rawValue];
        if (value) 
            [self cacheValue: value ofProperty: property changed: NO];
        else if (rawValue)
            Warn(@"Unable to decode Base64 data from property %@ of %@", property, _document);
    }
    return value;
}

- (NSDate*) getDateProperty: (NSString*)property {
    NSDate* value = [_properties objectForKey: property];
    if (!value) {
        id rawValue = [_document propertyForKey: property];
        if ([rawValue isKindOfClass: [NSString class]])
            value = [TDJSON dateWithJSONObject: rawValue];
        if (value) 
            [self cacheValue: value ofProperty: property changed: NO];
        else if (rawValue)
            Warn(@"Unable to decode date from property %@ of %@", property, _document);
    }
    return value;
}

- (TouchDatabase*) databaseForModelProperty: (NSString*)property {
    // This is a hook for subclasses to override if they need to, i.e. if the property
    // refers to a document in a different database.
    return _document.database;
}

- (TouchModel*) getModelProperty: (NSString*)property {
    // Model-valued properties are kept in raw form as document IDs, not mapped to TouchModel
    // references, to avoid reference loops.
    
    // First get the target document ID:
    NSString* rawValue = [self getValueOfProperty: property];
    if (!rawValue)
        return nil;
    
    // Look up the TouchDocument:
    if (![rawValue isKindOfClass: [NSString class]]) {
        Warn(@"Model-valued property %@ of %@ is not a string", property, _document);
        return nil;
    }
    TouchDocument* doc = [[self databaseForModelProperty: property] documentWithID: rawValue];
    if (!doc) {
        Warn(@"Unable to get document from property %@ of %@ (value='%@')",
             property, _document, rawValue);
        return nil;
    }
    
    // Ask factory to get/create model; if it doesn't know, use the declared class:
    TouchModel* value = [doc.database.modelFactory modelForDocument: doc];
    if (!value) {
        Class declaredClass = [[self class] classOfProperty: property];
        value = [declaredClass modelForDocument: doc];
        if (!value) 
            Warn(@"Unable to instantiate %@ from %@ -- property %@ of %@ (%@)",
                 declaredClass, doc, property, self, _document);
    }
    return value;
}

- (void) setModel: (TouchModel*)model forProperty: (NSString*)property {
    // Don't store the target TouchModel in the _properties dictionary, because this could create
    // a reference loop. Instead, just store the raw document ID. getModelProperty will map to the
    // model object when called.
    NSString* docID = model.document.documentID;
    NSAssert(docID || !model, 
             @"Cannot assign untitled %@ as the value of model property %@.%@ -- save it first",
             model.document, [self class], property);
    [self setValue: docID ofProperty: property];
}

+ (IMP) impForGetterOfProperty: (NSString*)property ofClass: (Class)propertyClass {
    if (propertyClass == Nil || propertyClass == [NSString class]
             || propertyClass == [NSNumber class] || propertyClass == [NSArray class]
             || propertyClass == [NSDictionary class])
        return [super impForGetterOfProperty: property ofClass: propertyClass];  // Basic classes (including 'id')
    else if (propertyClass == [NSData class]) {
        return imp_implementationWithBlock(^id(TouchModel* receiver) {
            return [receiver getDataProperty: property];
        });
    } else if (propertyClass == [NSDate class]) {
        return imp_implementationWithBlock(^id(TouchModel* receiver) {
            return [receiver getDateProperty: property];
        });
    } else if ([propertyClass isSubclassOfClass: [TouchModel class]]) {
        return imp_implementationWithBlock(^id(TouchModel* receiver) {
            return [receiver getModelProperty: property];
        });
    } else {
        return NULL;  // Unsupported
    }
}

+ (IMP) impForSetterOfProperty: (NSString*)property ofClass: (Class)propertyClass {
    if ([propertyClass isSubclassOfClass: [TouchModel class]]) {
        return imp_implementationWithBlock(^(TouchModel* receiver, TouchModel* value) {
            [receiver setModel: value forProperty: property];
        });
    } else {
        return [super impForSetterOfProperty: property ofClass: propertyClass];
    }
}


#pragma mark - KVO:


// TouchDocuments (and transitively their models) have only weak references from the TouchDatabase,
// so they may be dealloced if not used in a while. This is very bad if they have any observers, as
// the observation reference will dangle and cause crashes or mysterious bugs.
// To work around this, turn observation into a string reference by doing a retain.
// This may result in reference cycles if two models observe each other; not sure what to do about
// that yet!

- (void) addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context {
    [super addObserver: observer forKeyPath: keyPath options: options context: context];
    if (observer != self)
        [self retain];
}

- (void) removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    [super removeObserver: observer forKeyPath: keyPath];
    if (observer != self)
        [self retain];
    [self release];
}


#pragma mark - ATTACHMENTS:


- (NSArray*) attachmentNames {
    NSArray* names = [_document.currentRevision attachmentNames];
    if (!_changedAttachments)
        return names;
    
    NSMutableArray* nuNames = names ? [[names mutableCopy] autorelease] : [NSMutableArray array];
    for (NSString* name in _changedAttachments.allKeys) {
        TouchAttachment* attach = [_changedAttachments objectForKey: name];
        if ([attach isKindOfClass: [TouchAttachment class]]) {
            if (![nuNames containsObject: name])
                [nuNames addObject: name];
        } else
            [nuNames removeObject: name];
    }
    return nuNames;
}

- (TouchAttachment*) attachmentNamed: (NSString*)name {
    id attachment = [_changedAttachments objectForKey: name];
    if (attachment) {
        if ([attachment isKindOfClass: [TouchAttachment class]])
            return attachment;
        else
            return nil;
    }
    return [_document.currentRevision attachmentNamed: name];
}


- (void) addAttachment: (TouchAttachment*)attachment named: (NSString*)name {
    Assert(name);
    Assert(!attachment.name, @"Attachment already attached to another revision");
    if (attachment == [self attachmentNamed: name])
        return;
    
    if (!_changedAttachments)
        _changedAttachments = [[NSMutableDictionary alloc] init];
    [_changedAttachments setObject: (attachment ? attachment : [NSNull null])
                            forKey: name];
    attachment.name = name;
    [self markNeedsSave];
}

- (void) removeAttachmentNamed: (NSString*)name {
    [self addAttachment: nil named: name];
}


- (NSDictionary*) attachmentDataToSave {
    NSDictionary* attachments = [_document.properties objectForKey: @"_attachments"];
    if (!_changedAttachments)
        return attachments;
    
    NSMutableDictionary* nuAttach = attachments ? [[attachments mutableCopy] autorelease]
                                                : [NSMutableDictionary dictionary];
    for (NSString* name in _changedAttachments.allKeys) {
        // Yes, we are putting TDAttachment objects into the JSON-compatible dictionary.
        // The TouchDocument will process & convert these before actually storing the JSON.
        TouchAttachment* attach = [_changedAttachments objectForKey: name];
        if ([attach isKindOfClass: [TouchAttachment class]])
            [nuAttach setObject: attach forKey: name];
        else
            [nuAttach removeObjectForKey: name];
    }
    return nuAttach;
}


@end
