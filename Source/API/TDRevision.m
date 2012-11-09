//
//  TouchRevision.m
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDBPrivate.h"
#import "TD_Database+Insertion.h"
#import "TD_Revision.h"
#import "TDStatus.h"


@implementation TDRevision
{
    TDDocument* _document;
    TD_Revision* _rev;
    BOOL _checkedProperties;
}


- (id)initWithDocument: (TDDocument*)doc revision: (TD_Revision*)rev {
    Assert(doc != nil);
    Assert(rev != nil);
    self = [super init];
    if (self) {
        _document = doc;
        _rev = rev;
    }
    return self;
}


- (id)initWithTDDB: (TD_Database*)tddb revision: (TD_Revision*)rev {
    TDDocument* doc = [tddb.touchDatabase documentWithID: rev.docID];
    return [self initWithDocument: doc revision: rev];
}


- (NSString*) description {
    return $sprintf(@"%@[%@/%@]", [self class], _document.abbreviatedID, _rev.revID);
}


@synthesize document=_document, rev=_rev;

- (TDDatabase*) database {return _document.database;}
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
            revision = [_document revisionFromRev: rev];
        [history insertObject: revision atIndex: 0];  // reverse into forwards order
    }
    return history;
}


#pragma mark - SAVING:


- (TDRevision*) putProperties: (NSDictionary*)properties
                           error: (NSError**)outError
{
    return [_document putProperties: properties
                          prevRevID: _rev.revID
                              error: outError];
}


- (TDRevision*) deleteDocument: (NSError**)outError {
    return [self putProperties: nil error: outError];
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
