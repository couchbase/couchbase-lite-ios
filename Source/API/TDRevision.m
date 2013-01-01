//
//  TDRevision.m
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDBPrivate.h"
#import "TD_Database+Insertion.h"
#import "TD_Revision.h"
#import "TDStatus.h"


@implementation TDRevisionBase
{
    TDDocument* _document;
}

@synthesize document=_document;

- (id)initWithDocument: (TDDocument*)doc {
    Assert(doc != nil);
    self = [super init];
    if (self) {
        _document = doc;
    }
    return self;
}

- (TDDatabase*) database        {return _document.database;}
- (NSString*) revisionID        {return nil;}
- (SequenceNumber) sequence     {return 0;}
- (NSDictionary*) properties    {AssertAbstractMethod();}

- (NSDictionary*) userProperties {
    NSDictionary* rep = self.properties;
    if (!rep)
        return nil;
    NSMutableDictionary* props = [NSMutableDictionary dictionary];
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


- (BOOL) isDeleted {
    id del = self.properties[@"_deleted"];
    return del == nil || del == $false;
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


- (TDAttachment*) attachmentNamed: (NSString*)name {
    NSDictionary* metadata = [self attachmentMetadataFor: name];
    if (!metadata)
        return nil;
    return [[TDAttachment alloc] initWithRevision: self name: name metadata: metadata];
}


- (NSArray*) attachments {
    return [self.attachmentNames my_map: ^(NSString* name) {
        return [self attachmentNamed: name];
    }];
}


@end




@implementation TDRevision
{
    TD_Revision* _rev;
    BOOL _checkedProperties;
}


- (id)initWithDocument: (TDDocument*)doc revision: (TD_Revision*)rev {
    Assert(rev != nil);
    self = [super initWithDocument: doc];
    if (self) {
        _rev = rev;
    }
    return self;
}


- (id)initWithTDDB: (TD_Database*)tddb revision: (TD_Revision*)rev {
    TDDocument* doc = [tddb.touchDatabase documentWithID: rev.docID];
    return [self initWithDocument: doc revision: rev];
}


- (NSString*) description {
    return $sprintf(@"%@[%@/%@]", [self class], self.document.abbreviatedID, _rev.revID);
}


- (BOOL) isEqual: (id)object {
    if (object == self)
        return YES;
    else if (![object isKindOfClass: [TDRevision class]])
        return NO;
    return self.document == [object document] && $equal(_rev.revID, [object revisionID]);
}


@synthesize rev=_rev;

- (NSString*) revisionID    {return _rev.revID;}
- (BOOL) isDeleted          {return _rev.deleted;}


- (SequenceNumber) sequence {
    SequenceNumber sequence = _rev.sequence;
    if (sequence == 0) {
        TDStatus status = [self.database.tddb loadRevisionBody: _rev options: 0];
        if (TDStatusIsError(status))
            Warn(@"Couldn't get sequence of %@: %d", self, status);
        sequence = _rev.sequence;
    }
    return sequence;
}


- (NSDictionary*) properties {
    NSDictionary* properties = _rev.properties;
    if (!properties && !_checkedProperties) {
        TDStatus status = [self.database.tddb loadRevisionBody: _rev options: 0];
        if (TDStatusIsError(status))
            Warn(@"Couldn't load properties of %@: %d", self, status);
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
    for (TD_Revision* rev in [self.database.tddb getRevisionHistory: _rev]) {
        TDRevision* revision;
        if ($equal(rev.revID, _rev.revID))
            revision = self;
        else
            revision = [self.document revisionFromRev: rev];
        [history insertObject: revision atIndex: 0];  // reverse into forwards order
    }
    return history;
}


#pragma mark - SAVING:


- (TDNewRevision*) newRevision {
    return [[TDNewRevision alloc] initWithDocument: self.document parent: self];
}


- (TDRevision*) putProperties: (NSDictionary*)properties
                           error: (NSError**)outError
{
    return [self.document putProperties: properties
                              prevRevID: _rev.revID
                                  error: outError];
}


- (TDRevision*) deleteDocument: (NSError**)outError {
    return [self putProperties: nil error: outError];
}


@end




#pragma mark - TDNEWREVISION


@implementation TDNewRevision
{
    TDDocument* _document;
    NSString* _parentRevID;
    NSMutableDictionary* _properties;
}

@synthesize document=_document, parentRevisionID=_parentRevID, properties=_properties;

- (id)initWithDocument: (TDDocument*)doc parent: (TDRevision*)parent {
    Assert(doc != nil);
    self = [super init];
    if (self) {
        _document = doc;
        _parentRevID = parent.revisionID;
        _properties = [parent.properties mutableCopy];
        if (!_properties)
            _properties = $mdict({@"_id", doc.documentID},
                                 {@"_rev", _parentRevID});
    }
    return self;
}

- (TDDatabase*) database {return _document.database;}

- (TDRevision*) parentRevision {
    return _parentRevID ? [_document revisionWithID: _parentRevID] : nil;
}

- (NSDictionary*) userProperties {
    NSDictionary* rep = self.properties;
    if (!rep)
        return nil;
    NSMutableDictionary* props = [NSMutableDictionary dictionary];
    for (NSString* key in rep) {
        if (![key hasPrefix: @"_"])
            props[key] = rep[key];
    }
    return props;
}

- (id) objectForKeyedSubscript: (NSString*)key {
    return _properties[key];
}

- (void) setObject: (id)object forKeyedSubscript: (NSString*)key {
    _properties[key] = object;
}

- (void) setIsDeleted:(BOOL)isDeleted {
    if (isDeleted)
        _properties[@"_deleted"] = $true;
    else
        [_properties removeObjectForKey: @"_deleted"];
}

- (TDRevision*) save: (NSError**)outError {
    return [_document putProperties: _properties prevRevID: _parentRevID error: outError];
}

- (void) addAttachment: (TDAttachment*)attachment named: (NSString*)name {
    Assert(attachment.revision == nil);
    NSMutableDictionary* atts = [_properties[@"_attachments"] mutableCopy];
    if (!atts)
        atts = $mdict();
    [atts setValue: attachment forKey: name];
    _properties[@"_attachments"] = atts;
    attachment.name = name;
    attachment.revision = self;
}

- (void) removeAttachmentNamed: (NSString*)name {
    [self addAttachment: nil named: name];
}

@end
