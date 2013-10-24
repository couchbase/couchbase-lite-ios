//
//  CBLUndoableModel.m
//  CouchbaseLite
//
//  Created by Zymantas on 2013-10-24.
//
//

#import "CBLUndoableModel.h"
#import "CBLModel_Internal.h"

@interface CBLUndoableModel ()
{
    bool _canUndo   :1;
}

@end

@implementation CBLUndoableModel

- (instancetype) initWithDocument: (CBLDocument*)document {
    self = [super initWithDocument: document];
    if (self) {
        if (document) {
            _canUndo = true;
        }
    }
    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - DOCUMENT / DATABASE:

- (void) setDocument: (CBLDocument*)document {
    NSUndoManager* undoManager = document.database.undoManager;
    if (undoManager) {
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(undoManagerDidCloseUndoGroupNotification:)
                                                     name: NSUndoManagerDidCloseUndoGroupNotification
                                                   object: undoManager];
    }
    
    [super setDocument: document];
}

- (void) setDatabase: (CBLDatabase*)db {
    if (db && db.undoManager) {
        NSUndoManager* undoManager = db.undoManager;
        if ([undoManager isUndoing] == NO && [undoManager isRedoing] == NO) {
            [[undoManager prepareWithInvocationTarget: self] undoCreateModel];
            _canUndo = false;
        }
    }
    
    [super setDatabase: db];
}

- (BOOL) deleteDocument:(NSError *__autoreleasing *)outError {
    NSUndoManager* undoManager = self.database.undoManager;
    if (undoManager && _canUndo && [undoManager isUndoing] == NO
                                    && [undoManager isRedoing] == NO) {
        NSDictionary* modelUndoData = $dict({@"currentProperties", [[self currentUserProperties] copy]},
                                            {@"database", self.database},
                                            {@"model", self});
        
        [[undoManager prepareWithInvocationTarget:self] undoDeleteModel: modelUndoData];
        _canUndo = false;
    }
    
    return [super deleteDocument: outError];
}

- (void) tdDocumentChanged:(CBLDocument *)doc {
    if (self.database.undoManager && self.saving == false
                                    && self.deleting == false) {
        [self.database.undoManager removeAllActionsWithTarget: self];
        _canUndo = true;
    }
    
    [super tdDocumentChanged: doc];
}

#pragma mark - PROPERTIES:

- (BOOL) setValue: (id)value ofProperty: (NSString*)property {
    NSUndoManager* undoManager = self.database.undoManager;
    if (undoManager && _canUndo && [undoManager isUndoing] == NO
                                    && [undoManager isRedoing] == NO) {
        NSDictionary* propertiesToUndo = [[self currentUserProperties] copy];
        if (propertiesToUndo == nil) {
            propertiesToUndo = [NSDictionary dictionary];
        }
        
        [[undoManager prepareWithInvocationTarget: self] undoSetProperties: propertiesToUndo];
        _canUndo = false;
    }
    
    return [super setValue: value ofProperty: property];
}

#pragma mark - ATTACHMENTS:

- (void) addAttachment: (CBLAttachment *)attachment named: (NSString*)name {
    Assert(name);
    Assert(!attachment.name, @"Attachment already attached to another revision");

    NSUndoManager* undoManager = self.database.undoManager;
    if (undoManager && _canUndo && [undoManager isUndoing] == NO
                                    && [undoManager isRedoing] == NO) {
        if (attachment == nil) {
            CBLAttachment *attachmentToRemove = [self attachmentNamed: name];
            NSDictionary *attachmentUndoData = $dict({@"attachmentBody", attachmentToRemove.body},
                                                     {@"attachmentContentType", attachmentToRemove.contentType},
                                                     {@"attachmentName", name});
            [[undoManager prepareWithInvocationTarget: self] undoRemoveAttachment: attachmentUndoData];
        }
        else {
            [[undoManager prepareWithInvocationTarget: self] undoAddAttachmentNamed: name];
        }
        
        _canUndo = false;
    }
    
    [super addAttachment: attachment named: name];
}

#pragma mark - UNDO MANAGER:

- (void) undoManagerDidCloseUndoGroupNotification: (NSNotification*)notification {
    _canUndo = true;
}

- (void) undoCreateModel {
    NSDictionary* modelUndoData = $dict({@"currentProperties", [[self currentUserProperties] copy]},
                                        {@"database", self.database},
                                        {@"model", self});
    
    [[self.database.undoManager prepareWithInvocationTarget: self] undoDeleteModel: modelUndoData];
    
    NSError *error = nil;
    if ([self deleteDocument: &error] == NO) {
        Warn(@"Error while undoing (deleting) created model = %@, error = %@", self, error);
    }
}

- (void) undoDeleteModel: (NSDictionary*)modelUndoData {
    self.database = modelUndoData[@"database"];
    
    [[self.database.undoManager prepareWithInvocationTarget: self] undoCreateModel];
    
    NSDictionary* currentProperties = modelUndoData[@"currentProperties"];
    NSSet* propertyNames = [[self class] propertyNames];
    
    [propertyNames enumerateObjectsUsingBlock:^(NSString* propertyName, BOOL* stop) {
        id value = currentProperties[propertyName];
        
        [self willChangeValueForKey: propertyName];
        [self setValue: value ofProperty: propertyName];
        [self didChangeValueForKey: propertyName];
    }];
}

- (void) undoSetProperties: (NSDictionary*)properties {
    [[self.database.undoManager prepareWithInvocationTarget: self] undoSetProperties: [self currentUserProperties]];
    
    NSSet* propertyNames = [[self class] propertyNames];
    [propertyNames enumerateObjectsUsingBlock:^(NSString* propertyName, BOOL* stop) {
        id value = properties[propertyName];
        
        [self willChangeValueForKey: propertyName];
        [self setValue: value ofProperty: propertyName];
        [self didChangeValueForKey: propertyName];
    }];
}

- (void) undoAddAttachmentNamed: (NSString*) name {
    CBLAttachment *attachmentToRemove = [self attachmentNamed: name];
    NSDictionary *attachmentUndoData = $dict({@"attachmentBody", attachmentToRemove.body},
                                             {@"attachmentContentType", attachmentToRemove.contentType},
                                             {@"attachmentName", name});
    [[self.database.undoManager prepareWithInvocationTarget: self] undoRemoveAttachment: attachmentUndoData];
    
    [self removeAttachmentNamed: name];
}

- (void) undoRemoveAttachment: (NSDictionary*)attachmentUndoData {
    NSData *attachmentBody = attachmentUndoData[@"attachmentBody"];
    NSString *attachmentContentType = attachmentUndoData[@"attachmentContentType"];
    NSString *attachmentName = attachmentUndoData[@"attachmentName"];
    
    [[self.database.undoManager prepareWithInvocationTarget:self] undoAddAttachmentNamed: attachmentName];
    
    CBLAttachment *attachment = [[CBLAttachment alloc] initWithContentType: attachmentContentType body: attachmentBody];
    [self addAttachment: attachment named: attachmentName];
}


@end
