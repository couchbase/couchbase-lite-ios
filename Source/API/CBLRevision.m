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
#import "CBLInternal.h"
#import "CBLDatabase+Attachments.h"
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
- (NSArray*) getRevisionHistory: (NSError**)outError {AssertAbstractMethod();}
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


- (BOOL) isDeletion {
    return self.properties.cbl_deleted;
}

- (BOOL) isGone {
    return self.properties.cbl_deleted || $castIf(NSNumber, self.properties[@"_removed"]).boolValue;
}


- (NSString*) description {
    return $sprintf(@"%@[%@/%@]", [self class], self.document.abbreviatedID,
                    (self.revisionID ?: @""));
}


- (id) debugQuickLookObject {
    return [CBLJSON stringWithJSONObject: self.properties
                                 options: CBLJSONWritingPrettyPrinted error: NULL];
}


#pragma mark - ATTACHMENTS:


- (NSDictionary*) attachmentMetadata {
    return $castIf(NSDictionary, (self.properties).cbl_attachments);
}


- (NSDictionary*) attachmentMetadataFor: (NSString*)name {
    id attachment = self.attachmentMetadata[name];
    if ([attachment isKindOfClass: [CBLAttachment class]])
        return [(CBLAttachment*)attachment metadata];
    else
        return $castIf(NSDictionary, attachment);
}


- (NSArray*) attachmentNames {
    return [self.attachmentMetadata allKeys];
}


- (CBLAttachment*) attachmentNamed: (NSString*)name {
    id attachment = self.attachmentMetadata[name];
    if ([attachment isKindOfClass: [CBLAttachment class]])
        return attachment;
    else if ([attachment isKindOfClass: [NSDictionary class]]) {
        return [[CBLAttachment alloc] initWithRevision: self name: name metadata: attachment];
    } else {
        return nil;
    }
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
    NSString* _parentRevID;   // Used only during validation, when parent may not be in DB
}


- (instancetype) initWithDocument: (CBLDocument*)doc revision: (CBL_Revision*)rev {
    Assert(rev != nil);
    self = [super initWithDocument: doc];
    if (self) {
        _rev = rev.copy; // copy it in case original is mutable!
    }
    return self;
}


- (instancetype) initWithDatabase: (CBLDatabase*)db
                         revision: (CBL_Revision*)rev
{
    CBLDocument* doc = [db documentWithID: rev.docID];
    return [self initWithDocument: doc revision: rev];
}

- (instancetype) initForValidationWithDatabase: (CBLDatabase*)db
                                      revision: (CBL_Revision*)rev
                              parentRevisionID: (CBL_RevID*)parentRevID
{
    self = [self initWithDatabase: db revision: rev];
    if (self) {
        _parentRevID = parentRevID.asString;
        _checkedProperties = YES;
    }
    return self;
}

- (id) debugQuickLookObject {
    if (self.propertiesAreLoaded)
        return [super debugQuickLookObject];
    else
        return $sprintf(@"{\n\t\"_id\":\"%@\",\n\t\"_rev\":\"%@\"\n}\n(sorry, data not loaded)",
                        self.document.documentID, self.revisionID);

}

- (BOOL) isEqual: (id)object {
    if (object == self)
        return YES;
    else if (![object isKindOfClass: [CBLSavedRevision class]])
        return NO;
    return self.document == [object document]
        && $equal(_rev.revID, ((CBLSavedRevision*)object).rev.revID);
}


@synthesize rev=_rev;

- (NSString*) revisionID        {return _rev.revIDString;}
- (BOOL) isDeletion             {return _rev.deleted;}
- (BOOL) propertiesAvailable    {return !_rev.missing;}


- (NSString*) parentRevisionID  {
    return _parentRevID ?: [_document.database.storage getParentRevision: _rev].revIDString;
}

- (CBLSavedRevision*) parentRevision  {
    if (_parentRevID)
        return [_document revisionWithID: _parentRevID];
    CBLDocument* document = _document;
    return [document revisionFromRev: [document.database.storage getParentRevision: _rev]];
}


- (bool) loadProperties {
    CBLStatus status;
    CBL_Revision* rev = [self.database revisionByLoadingBody: _rev status: &status];
    if (!rev) {
        Warn(@"Couldn't load body/sequence of %@: %d", self, status);
        return false;
    }
    _rev = rev;
#if DEBUG
    NSDictionary* properties = rev.properties;
    AssertEqual(properties[@"_id"], self.document.documentID);
    AssertEqual(properties[@"_rev"], self.revisionID);
    AssertEq([properties[@"_deleted"] boolValue], self.isDeletion);
#endif
    return true;
}


- (SequenceNumber) sequence {
    SequenceNumber sequence = 0;
    if (_rev.sequenceIfKnown > 0 || [self loadProperties])
        sequence = _rev.sequence;
    return sequence;
}


- (NSDictionary*) properties {
    NSDictionary* properties = _rev.properties;
    if (!_checkedProperties) {
        if (properties == nil) {
            if ([self loadProperties])
                properties = _rev.properties;
        } else if (!properties.cbl_id) {
            _rev = [_rev revisionByAddingBasicMetadata];
            properties = _rev.properties;
        }
        _checkedProperties = YES;
    }
    return properties;
}

- (BOOL) propertiesAreLoaded {
    return _rev.properties != nil;
}

- (NSData*) JSONData {
    NSData* json = _rev.asJSON;
    if (!json) {
        if ([self loadProperties])
            json = _rev.asJSON;
    }
    return json;
}


- (NSArray*) getRevisionHistory: (NSError**)outError {
    return [self getRevisionHistoryBackToRevisionIDs: nil error: outError];
}

- (NSArray*) getRevisionHistoryBackToRevisionIDs: (NSArray*)ancestorIDs
                                           error: (NSError**)outError
{
    NSMutableArray* history = $marray();
    for (CBL_RevID* revID in [self.database getRevisionHistory: _rev backToRevIDs: ancestorIDs]) {
        CBLSavedRevision* revision;
        if ($equal(revID, _rev.revID))
            revision = self;
        else
            revision = [self.document revisionWithRevID: revID withBody: NO];
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


@end




#pragma mark - CBLUNSAVEDREVISION


@implementation CBLUnsavedRevision
{
    NSString* _parentRevID;
    NSMutableDictionary* _properties;
}

@synthesize parentRevisionID=_parentRevID;
@dynamic isDeletion, userProperties;     // Necessary because this class redeclares them

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

- (void) setProperties: (NSMutableDictionary*)properties {
    if (_properties != properties) {
        _properties = [properties mutableCopy];
    }
}

- (NSMutableDictionary*)properties {
    return _properties;
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
    return [_document putProperties: _properties prevRevID: _parentRevID.cbl_asRevID
                      allowConflict: NO error: outError];
}

- (CBLSavedRevision*) saveAllowingConflict: (NSError**)outError {
    return [_document putProperties: _properties prevRevID: _parentRevID.cbl_asRevID
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
    NSMutableDictionary* atts = [_properties.cbl_attachments mutableCopy];
    if (!atts)
        atts = $mdict();
    [atts setValue: attachment forKey: name];
    _properties[@"_attachments"] = atts;
    attachment.name = name;
    
    // NOTE: Not setting the revision to the attachment object (attachment.revision = self) as
    // [1] The UnsavedRevision object is not used during save operation
    // [2] Setting the UnsavedRevision object here will cause the circular reference memory leak.
}

- (void) removeAttachmentNamed: (NSString*)name {
    [self _addAttachment: nil named: name];
}

@end
