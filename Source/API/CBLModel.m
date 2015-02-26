//
//  CBLModel.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/26/11.
//  Copyright (c) 2011-2013 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLModel_Internal.h"
#import "CBLModelFactory.h"
#import "CBLModelArray.h"
#import "CBLDatabase+Attachments.h"
#import "CouchbaseLitePrivate.h"
#import "CBLMisc.h"
#import "CBLBase64.h"

#import <objc/message.h>
#import <objc/runtime.h>


@implementation CBLModel

@dynamic type;


- (instancetype) initWithDocument: (nullable CBLDocument*)document
                       orDatabase: (nullable CBLDatabase*)database
{
    NSParameterAssert(document || database);
    self = [super init];
    if (self) {
        if (document) {
            LogTo(CBLModel, @"%@ initWithDocument: %@ @%p", self.class, document, document);
            self.document = document;
            [self didLoadFromDocument];
        } else {
            LogTo(CBLModel, @"%@ initWithDatabase: %@", self.class, database);
            _isNew = true;
            self.database = database;
        }
        [self awakeFromInitializer];
    }
    return self;
}


+ (instancetype) modelForNewDocumentInDatabase: (CBLDatabase*)database {
    NSParameterAssert(database);
    if (self == [CBLModel class]) {
        Warn(@"Couldn't create a model object for a new document from the base CBLModel class.");
        return nil;
    }

    CBLModel *model = [[self alloc] initWithDocument:nil orDatabase:database];
    NSString *documentType = [database.modelFactory documentTypeForClass:[self class]];
    if(documentType != nil){
        model.type = documentType;
    }
    return model;
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
        model = [[self alloc] initWithDocument: document orDatabase:nil];
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
    if(_needsSave)
        Warn(@"%@ dealloced with unsaved changes!", self); // should be impossible
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
        self.document = docID ? [db documentWithID: docID] : [db createDocument];
        LogTo(CBLModel, @"%@ made new document", self);
    } else {
        [self deleteDocument: nil];
    }
}


- (BOOL) deleteDocument: (NSError**)outError {
    CBLSavedRevision* rev = _document.currentRevision;
    if (!rev)
        return YES;
    LogTo(CBLModel, @"%@ Deleting document", self);
    [self willSave: nil];
    NSDictionary* properties = self.propertiesToSaveForDeletion;
    if (!properties) {
        properties = @{@"_deleted": $true};
    } else if (!properties.cbl_deleted) {
        NSMutableDictionary* nuProps = properties.mutableCopy;
        nuProps[@"_deleted"] = $true;
        properties = nuProps;
    }
    self.needsSave = NO;        // prevent any pending saves

    if (![rev createRevisionWithProperties: properties error: outError])
        return NO;
    return YES;
}


- (NSDictionary*) propertiesToSaveForDeletion {
    return @{@"_deleted": $true, @"_rev": _document.currentRevision.revisionID};
}


- (void) awakeFromInitializer {
    // subclasses can override this
}

- (void) didLoadFromDocument {
    // subclasses can override this
}


// Respond to an external change (likely from sync). This is called by my CBLDocument.
- (void) document: (CBLDocument*)doc didChange:(CBLDatabaseChange*)change {
    NSAssert(doc == _document, @"Notified for wrong document");
    if (_saving)
        return;  // this is just an echo from my -justSave: method, below, so ignore it
    
    LogTo(CBLModel, @"%@ External change (rev=%@)", self, _document.currentRevisionID);
    _isNew = false;
    [self markExternallyChanged];
    
    // Prepare to send KVO notifications about all my properties in case they changed:
    NSSet* keys = [[self class] propertyNames];
    for (NSString* key in keys)
        [self willChangeValueForKey: key];

    if (doc.isDeleted) {
        // If doc was deleted, revert any unsaved changes and mark doc as unchanged:
        _properties = nil;
        _changedNames = nil;
        _changedAttachments = nil;
        self.needsSave = NO;
        // Detach from document:
        _document.modelObject = nil;
        _document = nil;

    } else {
        // Otherwise, remove unchanged cached values in _properties:
        if (_changedNames && _properties) {
            NSMutableSet* removeKeys = [NSMutableSet setWithArray: [_properties allKeys]];
            [removeKeys minusSet: _changedNames];
            [_properties removeObjectsForKeys: removeKeys.allObjects];
        } else {
            _properties = nil;
        }
        [self didLoadFromDocument];
    }

    // Send KVO notifications about all my properties:
    for (NSString* key in keys)
        [self didChangeValueForKey: key];
}


- (NSTimeInterval) timeSinceExternallyChanged {
    return CFAbsoluteTimeGetCurrent() - _changedTime;
}

- (void) markExternallyChanged {
    _changedTime = CFAbsoluteTimeGetCurrent();
}


- (void) revertChanges {
    if (!_needsSave)
        return;

    // Send KVO notifications about all changed properties:
    NSArray* changedKeys = _changedNames.allObjects;
    for (NSString* key in changedKeys)
        [self willChangeValueForKey: key];

    [_properties removeObjectsForKeys: changedKeys];
    _changedNames = nil;
    _changedAttachments = nil;
    self.needsSave = NO;

    for (NSString* key in changedKeys)
        [self didChangeValueForKey: key];
}


#pragma mark - SAVING:


@synthesize isNew=_isNew, autosaves=_autosaves;


- (NSTimeInterval) autosaveDelay {
    return 0.0;
}


- (void) scheduleAutosave {
    [self.database doAsyncAfterDelay: self.autosaveDelay block: ^{
        [self save: NULL];
    }];
}


- (void) setAutosaves: (bool) autosaves {
    if (autosaves != _autosaves) {
        _autosaves = autosaves;
        if (_autosaves && _needsSave) {
            [self scheduleAutosave];
        }
    }
}


- (void) markNeedsSave {
    if (_autosaves && !_needsSave)
        [self scheduleAutosave];
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
    bool ok;

    _saving = true;
    @try {
        ok = [_document putProperties: properties error: &error];
    }@finally {
        _saving = false;
    }
    
    if (!ok) {
        if (outError)
            *outError = error;
        else
            Warn(@"%@: Save failed: %@", self, error);
        return NO;
    }
    LogTo(CBLModel, @"%@ Saved as rev %@", self, _document.currentRevisionID);
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
            model->_saving = true; // Leave _saving set till after transaction ends
        }
        return YES;
    }];
    for (CBLModel* model in models) {
        model->_saving = false; // Reset _saving now that docs are saved
        if (saved)
            [model didSave];
    }
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
    else if ([value isKindOfClass: [NSURL class]])
        value = [value absoluteString];
    else if ([value isKindOfClass: [CBLModel class]])
        value = ((CBLModel*)value).document.documentID;
    else if ([value isKindOfClass: [NSArray class]]) {
        if ([value isKindOfClass: [CBLModelArray class]])
            value = [value docIDs];
        else
            value = [value my_map:^id(id obj) { return [self externalizePropertyValue: obj]; }];
    } else if ([value conformsToProtocol: @protocol(CBLJSONEncoding)]) {
        value = [(id<CBLJSONEncoding>)value encodeAsJSON];
    }
    return value;
}


- (NSDictionary*) propertiesToSave {
    NSMutableDictionary* properties = [_document.properties mutableCopy];
    if (!properties)
        properties = [NSMutableDictionary dictionaryWithObject: _document.documentID
                                                        forKey: @"_id"];
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


- (void) markPropertyNeedsSave: (NSString*)property {
    if (_properties[property] != nil && ![_changedNames containsObject: property]) {
        if (!_changedNames)
            _changedNames = [[NSMutableSet alloc] init];
        [_changedNames addObject: property];
        [self markNeedsSave];
    }
}


- (id) getValueOfProperty: (NSString*)property {
    id value = _properties[property];
    if (!value && !_isNew && ![_changedNames containsObject: property]) {
        value = [_document propertyForKey: property];
    }
    return value;
}

- (id) getValueOfProperty: (NSString*)property ofClass: (Class)klass {
    id value = _properties[property];
    if (!value && !_isNew && ![_changedNames containsObject: property]) {
        value = [_document propertyForKey: property];
        if (![value isKindOfClass: klass])
            value = nil;
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


+ (Class) itemClassForArrayProperty: (NSString*)property {
    SEL sel = NSSelectorFromString([property stringByAppendingString: @"ItemClass"]);
    if ([self respondsToSelector: sel]) {
        return (Class)objc_msgSend(self, sel);
    }
    return Nil;
}

+ (NSString*) inverseRelationForArrayProperty: (NSString*)property {
    SEL sel = NSSelectorFromString([property stringByAppendingString: @"InverseRelation"]);
    if ([self respondsToSelector: sel]) {
        return (NSString*)objc_msgSend(self, sel);
    }
    return nil;
}



- (CBLDatabase*) databaseForModelProperty: (NSString*)property {
    // This is a hook for subclasses to override if they need to, i.e. if the property
    // refers to a document in a different database.
    return _document.database;
}

- (CBLModel*) modelWithDocID: (NSString*)docID
                 forProperty: (NSString*)property
                     ofClass: (Class)declaredClass
{
    CBLDocument* doc = [[self databaseForModelProperty: property] documentWithID: docID];
    if (!doc) {
        Warn(@"Unable to get document from property %@ of %@ (value='%@')",
             property, _document, docID);
        return nil;
    }
    
    // Ask factory to get/create model; if it doesn't know, use the declared class:
    CBLModel* value = [doc.database.modelFactory modelForDocument: doc];
    if (!value) {
        if (!declaredClass)
            declaredClass = [[self class] classOfProperty: property];
        value = [declaredClass modelForDocument: doc];
        if (!value)
            Warn(@"Unable to instantiate %@ from %@ -- property %@ of %@ (%@)",
                 declaredClass, doc, property, self, _document);
    }
    return value;
}


// Queries to find the value of a model-valued array property that's an inverse relation.
- (NSArray*) findInverseOfRelation: (NSString*)relation
                         fromClass: (Class)fromClass
{
    CBLModelFactory* factory = self.database.modelFactory;
    CBLQueryBuilder* builder = [factory queryBuilderForClass: fromClass property: relation];
    if (!builder) {
        NSPredicate* pred;
        if (fromClass) {
            NSArray* types = [self.database.modelFactory documentTypesForClass: fromClass];
            Assert(types.count > 0, @"Class %@ is not registered for any document types",
                   fromClass);
            pred = [NSPredicate predicateWithFormat: @"type in %@ and %K = $DOCID",
                                 types, relation];
        } else {
            pred = [NSPredicate predicateWithFormat: @"%K = $DOCID", relation];
        }
        NSError* error;
        builder = [[CBLQueryBuilder alloc] initWithDatabase: self.database
                                                     select: nil
                                             wherePredicate: pred
                                                    orderBy: nil
                                                      error: &error];
        Assert(builder, @"Couldn't create query builder: %@", error);
        [factory setQueryBuilder: builder forClass: fromClass property:relation];
    }

    CBLQuery* q = [builder createQueryWithContext: @{@"DOCID": self.document.documentID}];
    NSError* error;
    CBLQueryEnumerator* e = [q run: &error];
    if (!e) {
        Warn(@"Querying for inverse of %@.%@ failed: %@", fromClass, relation, error);
        return nil;
    }
    NSMutableArray* docIDs = $marray();
    for (CBLQueryRow* row in e)
        [docIDs addObject: row.documentID];
    return [[CBLModelArray alloc] initWithOwner: self
                                       property: nil
                                      itemClass: fromClass
                                         docIDs: docIDs];
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


- (void) setAttachmentNamed: (NSString*)name
            withContentType: (NSString*)mimeType
                    content: (NSData*)content
{
    CBLAttachment* attachment = nil;
    if (content)
        attachment = [[CBLAttachment alloc] _initWithContentType: mimeType body: content];
    [self _addAttachment: attachment named: name];
}

- (void) setAttachmentNamed: (NSString*)name
            withContentType: (NSString*)mimeType
                 contentURL: (NSURL*)fileURL
{
    CBLAttachment* attachment = nil;
    if (fileURL)
        attachment = [[CBLAttachment alloc] _initWithContentType: mimeType body: fileURL];
    [self _addAttachment: attachment named: name];
}


- (void) _addAttachment: (CBLAttachment*)attachment named: (NSString*)name {
    Assert(name);
    if (!_changedAttachments)
        _changedAttachments = [[NSMutableDictionary alloc] init];
    _changedAttachments[name] = (attachment ? attachment : [NSNull null]);
    attachment.name = name;
    [self markNeedsSave];
}

- (void) removeAttachmentNamed: (NSString*)name {
    if (_changedAttachments[name] || _document.currentRevision.attachmentMetadata[name]) {
        [self _addAttachment: nil named: name];
    }
}


- (NSDictionary*) attachmentDataToSave {
    NSDictionary* attachments = (_document.properties).cbl_attachments;
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
    return nuAttach.count ? nuAttach : nil;
}


@end
