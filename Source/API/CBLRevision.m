//
//  CBLRevision.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBLDatabase+Insertion.h"
#import "CBL_Revision.h"
#import "CBLStatus.h"


@implementation CBLRevision
{
    @protected
    __weak CBLDocument* _document;
}

@synthesize document=_document;

- (instancetype) initWithDocument: (CBLDocument*)doc {
    self = [super init];
    if (self) {
        _document = doc;
    }
    return self;
}

- (CBLDatabase*) database                            {return _document.database;}
- (NSString*) revisionID                             {return nil;}
- (NSString*) parentRevisionID                       {AssertAbstractMethod();}
- (CBLSavedRevision*) parentRevision                 {AssertAbstractMethod();}
- (NSArray*) getRevisionHistory: (NSError**)outError {AssertAbstractMethod();};
- (NSDictionary*) properties                         {AssertAbstractMethod();}
- (SequenceNumber) sequence                          {return 0;}

- (NSDictionary*) userProperties {
    NSDictionary* rep = self.properties;
    if (!rep)
        return nil;
    NSMutableDictionary* props = [NSMutableDictionary dictionaryWithCapacity: rep.count];
    for (NSString* key in rep) {
        if (![key hasPrefix: @"_"])
            props[key] = rep[key];
    }
    return props;
}

- (id) propertyForKey: (NSString*)key {
    return (self.properties)[key];
}

- (id)objectForKeyedSubscript:(NSString*)key {
    return (self.properties)[key];
}


static inline BOOL isTruthy(id value) {
    return value != nil && value != $false;
}

- (BOOL) isDeletion {
    return isTruthy(self.properties[@"_deleted"]);
}

#ifdef CBL_DEPRECATED
- (BOOL) isDeleted {
    return self.isDeletion;
}
#endif

- (BOOL) isGone {
    return isTruthy(self.properties[@"_deleted"]) || isTruthy(self.properties[@"_removed"]);
}


- (NSString*) description {
    return $sprintf(@"%@[%@/%@]", [self class], self.document.abbreviatedID,
                    (self.revisionID ?: @""));
}


#pragma mark - ATTACHMENTS:


- (NSDictionary*) attachmentMetadata {
    return $castIf(NSDictionary, (self.properties)[@"_attachments"]);
}


- (NSDictionary*) attachmentMetadataFor: (NSString*)name {
    return $castIf(NSDictionary, (self.attachmentMetadata)[name]);
}


- (NSArray*) attachmentNames {
    return [self.attachmentMetadata allKeys];
}


- (CBLAttachment*) attachmentNamed: (NSString*)name {
    NSDictionary* metadata = [self attachmentMetadataFor: name];
    if (!metadata)
        return nil;
    return [[CBLAttachment alloc] initWithRevision: self name: name metadata: metadata];
}


- (NSArray*) attachments {
    return [self.attachmentNames my_map: ^(NSString* name) {
        return [self attachmentNamed: name];
    }];
}


@end




@implementation CBLSavedRevision
{
    CBL_Revision* _rev;
    BOOL _checkedProperties;
}


- (instancetype) initWithDocument: (CBLDocument*)doc revision: (CBL_Revision*)rev {
    Assert(rev != nil);
    self = [super initWithDocument: doc];
    if (self) {
        _rev = rev.copy; // copy it in case original is mutable!
    }
    return self;
}


- (instancetype) initWithDatabase: (CBLDatabase*)db revision: (CBL_Revision*)rev {
    CBLDocument* doc = [db documentWithID: rev.docID];
    return [self initWithDocument: doc revision: rev];
}


- (BOOL) isEqual: (id)object {
    if (object == self)
        return YES;
    else if (![object isKindOfClass: [CBLSavedRevision class]])
        return NO;
    return self.document == [object document] && $equal(_rev.revID, [object revisionID]);
}


@synthesize rev=_rev;

- (NSString*) revisionID    {return _rev.revID;}
- (BOOL) isDeletion          {return _rev.deleted;}
- (BOOL) propertiesAvailable{return !_rev.missing;}


- (NSString*) parentRevisionID  {
    return [_document.database getParentRevision: _rev].revID;
}

- (CBLSavedRevision*) parentRevision  {
    CBLDocument* document = _document;
    return [document revisionFromRev: [document.database getParentRevision: _rev]];
}


- (bool) loadProperties {
    CBLStatus status;
    CBL_Revision* rev = [self.database revisionByLoadingBody: _rev options: 0 status: &status];
    if (!rev) {
        Warn(@"Couldn't load body/sequence of %@: %d", self, status);
        return false;
    }
    _rev = rev;
    return true;
}


- (SequenceNumber) sequence {
    SequenceNumber sequence = _rev.sequence;
    if (sequence == 0 && [self loadProperties])
            sequence = _rev.sequence;
    return sequence;
}


- (NSDictionary*) properties {
    NSDictionary* properties = _rev.properties;
    if (!properties && !_checkedProperties) {
        if ([self loadProperties])
            properties = _rev.properties;
        _checkedProperties = YES;
    }
    return properties;
}

- (BOOL) propertiesAreLoaded {
    return _rev.properties != nil;
}


- (NSArray*) getRevisionHistory: (NSError**)outError {
    NSMutableArray* history = $marray();
    for (CBL_Revision* rev in [self.database getRevisionHistory: _rev]) {
        CBLSavedRevision* revision;
        if ($equal(rev.revID, _rev.revID))
            revision = self;
        else
            revision = [self.document revisionFromRev: rev];
        [history insertObject: revision atIndex: 0];  // reverse into forwards order
    }
    return history;
}


#pragma mark - SAVING:


- (CBLUnsavedRevision*) createRevision {
    return [[CBLUnsavedRevision alloc] initWithDocument: self.document parent: self];
}


- (CBLSavedRevision*) createRevisionWithProperties: (NSDictionary*)properties
                         error: (NSError**)outError
{
    return [self.document putProperties: properties
                              prevRevID: _rev.revID
                          allowConflict: NO
                                  error: outError];
}


- (CBLSavedRevision*) deleteDocument: (NSError**)outError {
    return [self createRevisionWithProperties: nil error: outError];
}


#ifdef CBL_DEPRECATED
- (CBLUnsavedRevision*) newRevision {
    return [self createRevision];
}
- (CBLSavedRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError {
    return [self createRevisionWithProperties: properties error: outError];
}
#endif

@end




#pragma mark - CBLNEWREVISION


@implementation CBLUnsavedRevision
{
    NSString* _parentRevID;
    NSMutableDictionary* _properties;
}

@synthesize parentRevisionID=_parentRevID, properties=_properties;

- (instancetype) initWithDocument: (CBLDocument*)doc parent: (CBLSavedRevision*)parent {
    Assert(doc != nil);
    self = [super initWithDocument: doc];
    if (self) {
        _parentRevID = parent.revisionID;
        _properties = [parent.properties mutableCopy];
        if (!_properties)
            _properties = $mdict({@"_id", doc.documentID},
                                 {@"_rev", _parentRevID});
    }
    return self;
}

- (CBLSavedRevision*) parentRevision {
    return _parentRevID ? [_document revisionWithID: _parentRevID] : nil;
}

- (NSArray*) getRevisionHistory: (NSError**)outError {
    CBLSavedRevision* parent = self.parentRevision;
    return parent ? [parent getRevisionHistory: outError] : @[];
    // (Don't include self in the array, because this revision doesn't really exist yet)
}

- (void) setUserProperties:(NSDictionary *)userProperties {
    NSMutableDictionary* newProps = userProperties.mutableCopy ?: $mdict();
    for (NSString* key in _properties) {
        if ([key hasPrefix: @"_"])
            newProps[key] = _properties[key];  // Preserve metadata properties
    }
    self.properties = newProps;
}

- (void) setObject: (id)object forKeyedSubscript: (NSString*)key {
    [_properties setValue: object forKey: key];
}

- (void) setIsDeletion:(BOOL)isDeleted {
    if (isDeleted)
        _properties[@"_deleted"] = $true;
    else
        [_properties removeObjectForKey: @"_deleted"];
}

- (CBLSavedRevision*) save: (NSError**)outError {
    return [_document putProperties: _properties prevRevID: _parentRevID
                      allowConflict: NO error: outError];
}

- (CBLSavedRevision*) saveAllowingConflict: (NSError**)outError {
    return [_document putProperties: _properties prevRevID: _parentRevID
                      allowConflict: YES error: outError];
}

- (void) setAttachmentNamed: (NSString*)name
            withContentType: (NSString*)mimeType
                    content: (NSData*)content
{
    [self _addAttachment: [[CBLAttachment alloc] _initWithContentType: mimeType body: content]
                  named: name];
}

- (void) setAttachmentNamed: (NSString*)name
            withContentType: (NSString*)mimeType
                 contentURL: (NSURL*)fileURL
{
    [self _addAttachment: [[CBLAttachment alloc] _initWithContentType: mimeType body: fileURL]
                  named: name];
}

- (void) _addAttachment: (CBLAttachment*)attachment named: (NSString*)name {
    NSMutableDictionary* atts = [_properties[@"_attachments"] mutableCopy];
    if (!atts)
        atts = $mdict();
    [atts setValue: attachment forKey: name];
    _properties[@"_attachments"] = atts;
    attachment.name = name;
    attachment.revision = self;
}

- (void) removeAttachmentNamed: (NSString*)name {
    [self _addAttachment: nil named: name];
}


#ifdef CBL_DEPRECATED
- (void) addAttachment: (CBLAttachment*)attachment named: (NSString*)name {
    Assert(attachment.revision == nil);
    [self _addAttachment: attachment named: name];
}
#endif

@end
