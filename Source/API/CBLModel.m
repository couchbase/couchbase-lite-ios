//
//  CBLModel.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/26/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "CBLModel.h"
#import "CBLModelFactory.h"
#import "CouchbaseLitePrivate.h"
#import "CBLMisc.h"
#import "CBLBase64.h"
#import <objc/runtime.h>


@interface CBLModel ()
@property (readwrite, retain) CBLDocument* document;
@property (readwrite) bool needsSave;
@end


@implementation CBLModel
{
    CBLDocument* _document;
    CFAbsoluteTime _changedTime;
    bool _autosaves :1;
    bool _isNew     :1;
    bool _needsSave :1;

    NSMutableDictionary* _properties;   // Cached property values, including changed values
    NSMutableSet* _changedNames;        // Names of properties that have been changed but not saved
    NSMutableDictionary* _changedAttachments;
}


- (instancetype) init {
    return [self initWithDocument: nil];
}

- (instancetype) initWithDocument: (CBLDocument*)document
{
    self = [super init];
    if (self) {
        if (document) {
            LogTo(CBLModel, @"%@ initWithDocument: %@ @%p", self.class, document, document);
            self.document = document;
            [self didLoadFromDocument];
        } else {
            _isNew = true;
            LogTo(CBLModel, @"%@ init", self);
        }
    }
    return self;
}


- (instancetype) initWithNewDocumentInDatabase: (CBLDatabase*)database {
    NSParameterAssert(database);
    self = [self initWithDocument: nil];
    if (self) {
        self.database = database;
    }
    return self;
}


+ (instancetype) modelForDocument: (CBLDocument*)document {
    NSParameterAssert(document);
    CBLModel* model = document.modelObject;
    if (model) {
        // Document already has a model; make sure it's type-compatible with the desired class
        NSAssert([model isKindOfClass: self], @"%@: %@ already has incompatible model %@",
                 self, document, model);
    } else if (self != [CBLModel class]) {
        // If invoked on a subclass of CBLModel, create an instance of that subclass:
        model = [[self alloc] initWithDocument: document];
    } else {
        // If invoked on CBLModel itself, ask the factory to instantiate the appropriate class:
        model = [document.database.modelFactory modelForDocument: document];
        if (!model)
            Warn(@"Couldn't figure out what model class to use for doc %@", document);
    }
    return model;
}


- (void) dealloc
{
    LogTo(CBLModel, @"%@ dealloc", self);
    Assert(!_needsSave, @"%@ dealloc with unsaved changes!", self);
    _document.modelObject = nil;
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]",
                self.class, CBLAbbreviate(self.document.documentID)];
}


#pragma mark - DOCUMENT / DATABASE:


- (CBLDocument*) document {
    return _document;
}


- (void) setDocument:(CBLDocument *)document {
    NSAssert(!_document && document, @"Can't change or clear document");
    NSAssert(document.modelObject == nil, @"Document already has a model");
    _document = document;
    _document.modelObject = self;
}


- (void) detachFromDocument {
    _document.modelObject = nil;
    _document = nil;
}


- (NSString*) idForNewDocumentInDatabase: (CBLDatabase*)db {
    return nil;  // subclasses can override this to customize the doc ID
}


- (CBLDatabase*) database {
    return _document.database;
}


- (void) setDatabase: (CBLDatabase*)db {
    if (db) {
        // On setting database, create a new untitled/unsaved CBLDocument:
        NSString* docID = [self idForNewDocumentInDatabase: db];
        self.document = docID ? [db documentWithID: docID] : [db untitledDocument];
        LogTo(CBLModel, @"%@ made new document", self);
    } else {
        [self deleteDocument: nil];
        [self detachFromDocument];  // detach immediately w/o waiting for success
    }
}


- (BOOL) deleteDocument: (NSError**)outError {
    CBLRevision* rev = _document.currentRevision;
    if (!rev)
        return YES;
    LogTo(CBLModel, @"%@ Deleting document", self);
    self.needsSave = NO;        // prevent any pending saves
    rev = [rev deleteDocument: outError];
    if (!rev)
        return NO;
    [self detachFromDocument];
    return YES;
}


- (void) didLoadFromDocument {
    // subclasses can override this
}


// Respond to an external change (likely from sync). This is called by my CBLDocument.
- (void) tdDocumentChanged: (CBLDocument*)doc {
    NSAssert(doc == _document, @"Notified for wrong document");
    LogTo(CBLModel, @"%@ External change (rev=%@)", self, _document.currentRevisionID);
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


@synthesize isNew=_isNew, autosaves=_autosaves;


- (NSTimeInterval) autosaveDelay {
    return 0.0;
}


- (void) setAutosaves: (bool) autosaves {
    if (autosaves != _autosaves) {
        _autosaves = autosaves;
        if (_autosaves && _needsSave)
            [self performSelector: @selector(save:) withObject: nil afterDelay: self.autosaveDelay];
    }
}


- (void) markNeedsSave {
    if (_autosaves && !_needsSave)
        [self performSelector: @selector(save:) withObject: nil afterDelay: self.autosaveDelay];
    self.needsSave = YES;
}


- (bool) needsSave {
    return _needsSave;
}


- (void) setNeedsSave: (bool)needsSave {
    if (needsSave != _needsSave) {
        _needsSave = needsSave;
        NSMutableSet* unsaved = self.database.unsavedModelsMutable;
        if (needsSave)
            [unsaved addObject: self];
        else
            [unsaved removeObject: self];
    }
}


- (void) willSave: (NSSet*)changedProperties {
    // Subclasses can override
}


- (void) didSave {
    if (!_needsSave || (!_changedNames && !_changedAttachments))
        return;
    _isNew = NO;
    _properties = nil;
    _changedNames = nil;
    _changedAttachments = nil;
    self.needsSave = NO;
}


// Internal version of -save: that doesn't invoke -didSave
- (BOOL) justSave: (NSError**)outError {
    if (!_needsSave || (!_changedNames && !_changedAttachments))
        return YES;
    [self willSave: _changedNames];
    NSDictionary* properties = self.propertiesToSave;
    LogTo(CBLModel, @"%@ Saving <- %@", self, properties);
    NSError* error;
    if (![_document putProperties: properties error: &error]) {
        if (outError)
            *outError = error;
        else
            Warn(@"%@: Save failed: %@", self, error);
        return NO;
    }
    return YES;
}


- (BOOL) save: (NSError**)outError {
    BOOL ok = [self justSave: outError];
    if (ok)
        [self didSave];
    return ok;
}


+ (BOOL) saveModels: (NSArray*)models error: (NSError**)outError {
    if (models.count == 0)
        return YES;
    CBLDatabase* db = [(CBLModel*)models[0] database];
    BOOL saved = [db inTransaction: ^{
        for (CBLModel* model in models) {
            NSAssert(model.database == db, @"Models must share a common db");
            if (![model justSave: outError])
                return NO;
        }
        return YES;
    }];
    if (saved)
        for (CBLModel* model in models)
            [model didSave];
    return saved;
}


#pragma mark - PROPERTIES:


- (NSDictionary*) currentProperties {
    NSMutableDictionary* properties = [_document.properties mutableCopy];
    if (!properties)
        properties = [[NSMutableDictionary alloc] init];
    for (NSString* key in _changedNames)
        [properties setValue: _properties[key] forKey: key];
    return properties;
}


+ (NSSet*) propertyNames {
    if (self == [CBLModel class])
        return [NSSet set]; // Ignore non-persisted properties declared on base CBLModel
    return [super propertyNames];
}

// Transforms cached property values back into JSON-compatible objects
- (id) externalizePropertyValue: (id)value {
    if ([value isKindOfClass: [NSData class]])
        value = [CBLBase64 encode: value];
    else if ([value isKindOfClass: [NSDate class]])
        value = [CBLJSON JSONObjectWithDate: value];
    else if ([value isKindOfClass: [NSDecimalNumber class]])
        value = [value stringValue];
    return value;
}


- (NSDictionary*) propertiesToSave {
    NSMutableDictionary* properties = [_document.properties mutableCopy];
    if (!properties)
        properties = [[NSMutableDictionary alloc] init];
    for (NSString* key in _changedNames) {
        id value = _properties[key];
        [properties setValue: [self externalizePropertyValue: value] forKey: key];
    }
    [properties setValue: self.attachmentDataToSave forKey: @"_attachments"];
    return properties;
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
    id value = _properties[property];
    if (!value && !_isNew && ![_changedNames containsObject: property]) {
        value = [_document propertyForKey: property];
    }
    return value;
}


- (BOOL) setValue: (id)value ofProperty: (NSString*)property {
    NSParameterAssert(_document);
    id curValue = [self getValueOfProperty: property];
    if (!$equal(value, curValue)) {
        LogTo(CBLModel, @"%@ .%@ := \"%@\"", self, property, value);
        [self cacheValue: value ofProperty: property changed: YES];
        [self markNeedsSave];
    }
    return YES;
}


#pragma mark - PROPERTY TRANSFORMATIONS:


- (NSData*) getDataProperty: (NSString*)property {
    NSData* value = _properties[property];
    if (!value) {
        id rawValue = [_document propertyForKey: property];
        if ([rawValue isKindOfClass: [NSString class]])
            value = [CBLBase64 decode: rawValue];
        if (value) 
            [self cacheValue: value ofProperty: property changed: NO];
        else if (rawValue)
            Warn(@"Unable to decode Base64 data from property %@ of %@", property, _document);
    }
    return value;
}

- (NSDate*) getDateProperty: (NSString*)property {
    NSDate* value = _properties[property];
    if (!value) {
        id rawValue = [_document propertyForKey: property];
        if ([rawValue isKindOfClass: [NSString class]])
            value = [CBLJSON dateWithJSONObject: rawValue];
        if (value) 
            [self cacheValue: value ofProperty: property changed: NO];
        else if (rawValue)
            Warn(@"Unable to decode date from property %@ of %@", property, _document);
    }
    return value;
}

- (NSDecimalNumber*) getDecimalNumberProperty: (NSString*)property {
    NSDecimalNumber* value = _properties[property];
    if (!value) {
        id rawValue = [_document propertyForKey: property];
        if ([rawValue isKindOfClass: [NSString class]])
            value = [NSDecimalNumber decimalNumberWithString: rawValue];
        if (value)
            [self cacheValue: value ofProperty: property changed: NO];
        else if (rawValue)
            Warn(@"Unable to decode date from property %@ of %@", property, _document);
    }
    return value;
}

- (CBLDatabase*) databaseForModelProperty: (NSString*)property {
    // This is a hook for subclasses to override if they need to, i.e. if the property
    // refers to a document in a different database.
    return _document.database;
}

- (CBLModel*) getModelProperty: (NSString*)property {
    // Model-valued properties are kept in raw form as document IDs, not mapped to CBLModel
    // references, to avoid reference loops.
    
    // First get the target document ID:
    NSString* rawValue = [self getValueOfProperty: property];
    if (!rawValue)
        return nil;
    
    // Look up the CBLDocument:
    if (![rawValue isKindOfClass: [NSString class]]) {
        Warn(@"Model-valued property %@ of %@ is not a string", property, _document);
        return nil;
    }
    CBLDocument* doc = [[self databaseForModelProperty: property] documentWithID: rawValue];
    if (!doc) {
        Warn(@"Unable to get document from property %@ of %@ (value='%@')",
             property, _document, rawValue);
        return nil;
    }
    
    // Ask factory to get/create model; if it doesn't know, use the declared class:
    CBLModel* value = [doc.database.modelFactory modelForDocument: doc];
    if (!value) {
        Class declaredClass = [[self class] classOfProperty: property];
        value = [declaredClass modelForDocument: doc];
        if (!value) 
            Warn(@"Unable to instantiate %@ from %@ -- property %@ of %@ (%@)",
                 declaredClass, doc, property, self, _document);
    }
    return value;
}

- (void) setModel: (CBLModel*)model forProperty: (NSString*)property {
    // Don't store the target CBLModel in the _properties dictionary, because this could create
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
        return imp_implementationWithBlock(^id(CBLModel* receiver) {
            return [receiver getDataProperty: property];
        });
    } else if (propertyClass == [NSDate class]) {
        return imp_implementationWithBlock(^id(CBLModel* receiver) {
            return [receiver getDateProperty: property];
        });
    } else if (propertyClass == [NSDecimalNumber class]) {
        return imp_implementationWithBlock(^id(CBLModel* receiver) {
            return [receiver getDecimalNumberProperty: property];
        });
    } else if ([propertyClass isSubclassOfClass: [CBLModel class]]) {
        return imp_implementationWithBlock(^id(CBLModel* receiver) {
            return [receiver getModelProperty: property];
        });
    } else {
        return NULL;  // Unsupported
    }
}

+ (IMP) impForSetterOfProperty: (NSString*)property ofClass: (Class)propertyClass {
    if ([propertyClass isSubclassOfClass: [CBLModel class]]) {
        return imp_implementationWithBlock(^(CBLModel* receiver, CBLModel* value) {
            [receiver setModel: value forProperty: property];
        });
    } else {
        return [super impForSetterOfProperty: property ofClass: propertyClass];
    }
}


#pragma mark - ATTACHMENTS:


- (NSArray*) attachmentNames {
    NSArray* names = [_document.currentRevision attachmentNames];
    if (!_changedAttachments)
        return names;
    
    NSMutableArray* nuNames = names ? [names mutableCopy] : [NSMutableArray array];
    for (NSString* name in _changedAttachments.allKeys) {
        CBLAttachment* attach = _changedAttachments[name];
        if ([attach isKindOfClass: [CBLAttachment class]]) {
            if (![nuNames containsObject: name])
                [nuNames addObject: name];
        } else
            [nuNames removeObject: name];
    }
    return nuNames;
}

- (CBLAttachment*) attachmentNamed: (NSString*)name {
    id attachment = _changedAttachments[name];
    if (attachment) {
        if ([attachment isKindOfClass: [CBLAttachment class]])
            return attachment;
        else
            return nil;
    }
    return [_document.currentRevision attachmentNamed: name];
}


- (void) addAttachment: (CBLAttachment*)attachment named: (NSString*)name {
    Assert(name);
    Assert(!attachment.name, @"Attachment already attached to another revision");
    if (attachment == [self attachmentNamed: name])
        return;
    
    if (!_changedAttachments)
        _changedAttachments = [[NSMutableDictionary alloc] init];
    _changedAttachments[name] = (attachment ? attachment : [NSNull null]);
    attachment.name = name;
    [self markNeedsSave];
}

- (void) removeAttachmentNamed: (NSString*)name {
    [self addAttachment: nil named: name];
}


- (NSDictionary*) attachmentDataToSave {
    NSDictionary* attachments = (_document.properties)[@"_attachments"];
    if (!_changedAttachments)
        return attachments;
    
    NSMutableDictionary* nuAttach = attachments ? [attachments mutableCopy]
                                                : [NSMutableDictionary dictionary];
    for (NSString* name in _changedAttachments.allKeys) {
        // Yes, we are putting CBLAttachment objects into the JSON-compatible dictionary.
        // The CBLDocument will process & convert these before actually storing the JSON.
        CBLAttachment* attach = _changedAttachments[name];
        if ([attach isKindOfClass: [CBLAttachment class]])
            nuAttach[name] = attach;
        else
            [nuAttach removeObjectForKey: name];
    }
    return nuAttach;
}


@end
