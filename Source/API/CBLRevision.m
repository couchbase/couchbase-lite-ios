//
//  CBLRevision.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrivate.h"
#import "CBLDatabase+Insertion.h"
#import "CBL_Revision.h"
#import "CBLStatus.h"


@implementation CBLRevisionBase
{
    @protected
    CBLDocument* _document;
}

@synthesize document=_document;

- (instancetype) initWithDocument: (CBLDocument*)doc {
    self = [super init];
    if (self) {
        _document = doc;
    }
    return self;
}

- (CBLDatabase*) database       {return _document.database;}
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
    return del != nil && del != $false;
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




@implementation CBLRevision
{
    CBL_Revision* _rev;
    BOOL _checkedProperties;
}


- (instancetype) initWithDocument: (CBLDocument*)doc revision: (CBL_Revision*)rev {
    Assert(rev != nil);
    self = [super initWithDocument: doc];
    if (self) {
        _rev = rev;
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
    else if (![object isKindOfClass: [CBLRevision class]])
        return NO;
    return self.document == [object document] && $equal(_rev.revID, [object revisionID]);
}


@synthesize rev=_rev;

- (NSString*) revisionID    {return _rev.revID;}
- (BOOL) isDeleted          {return _rev.deleted;}


- (SequenceNumber) sequence {
    SequenceNumber sequence = _rev.sequence;
    if (sequence == 0) {
        CBLStatus status = [self.database loadRevisionBody: _rev options: 0];
        if (CBLStatusIsError(status))
            Warn(@"Couldn't get sequence of %@: %d", self, status);
        sequence = _rev.sequence;
    }
    return sequence;
}


- (NSDictionary*) properties {
    NSDictionary* properties = _rev.properties;
    if (!properties && !_checkedProperties) {
        CBLStatus status = [self.database loadRevisionBody: _rev options: 0];
        if (CBLStatusIsError(status))
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
    for (CBL_Revision* rev in [self.database getRevisionHistory: _rev]) {
        CBLRevision* revision;
        if ($equal(rev.revID, _rev.revID))
            revision = self;
        else
            revision = [self.document revisionFromRev: rev];
        [history insertObject: revision atIndex: 0];  // reverse into forwards order
    }
    return history;
}


#pragma mark - SAVING:


- (CBLNewRevision*) newRevision {
    return [[CBLNewRevision alloc] initWithDocument: self.document parent: self];
}


- (CBLRevision*) putProperties: (NSDictionary*)properties
                           error: (NSError**)outError
{
    return [self.document putProperties: properties
                              prevRevID: _rev.revID
                                  error: outError];
}


- (CBLRevision*) deleteDocument: (NSError**)outError {
    return [self putProperties: nil error: outError];
}


@end




#pragma mark - CBLNEWREVISION


@implementation CBLNewRevision
{
    NSString* _parentRevID;
    NSMutableDictionary* _properties;
}

@synthesize parentRevisionID=_parentRevID, properties=_properties;

- (instancetype) initWithDocument: (CBLDocument*)doc parent: (CBLRevision*)parent {
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

- (CBLRevision*) parentRevision {
    return _parentRevID ? [_document revisionWithID: _parentRevID] : nil;
}

- (void) setObject: (id)object forKeyedSubscript: (NSString*)key {
    [_properties setValue: object forKey: key];
}

- (void) setIsDeleted:(BOOL)isDeleted {
    if (isDeleted)
        _properties[@"_deleted"] = $true;
    else
        [_properties removeObjectForKey: @"_deleted"];
}

- (CBLRevision*) save: (NSError**)outError {
    return [_document putProperties: _properties prevRevID: _parentRevID error: outError];
}

- (void) addAttachment: (CBLAttachment*)attachment named: (NSString*)name {
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
