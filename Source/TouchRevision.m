//
//  TouchRevision.m
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDBPrivate.h"
#import "TDDatabase+Insertion.h"
#import "TDRevision.h"
#import "TDStatus.h"


@implementation TouchRevision


- (id)initWithDocument: (TouchDocument*)doc revision: (TDRevision*)rev {
    self = [super init];
    if (self) {
        _document = [doc retain];
        _rev = [rev retain];
    }
    return self;
}

- (void)dealloc {
    [_document release];
    [_rev release];
    [super dealloc];
}


- (NSString*) description {
    return $sprintf(@"%@[%@/%@]", [self class], _document.abbreviatedID, _rev.revID);
}


@synthesize document=_document, rev=_rev;

- (TouchDatabase*) database {return _document.database;}
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
    if (!properties) {
        TDStatus status = [self.database.tddb loadRevisionBody: _rev options: 0];
        if (TDStatusIsError(status))
            Warn(@"Couldn't load properties of %@: %d", self, status);
        properties = _rev.properties;
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
    for (TDRevision* rev in [self.database.tddb getRevisionHistory: _rev]) {
        TouchRevision* revision;
        if ($equal(rev.revID, _rev.revID))
            revision = self;
        else
            revision = [_document revisionFromRev: rev];
        [history insertObject: revision atIndex: 0];  // reverse into forwards order
    }
    return history;
}


#pragma mark - SAVING:


- (TouchRevision*) putProperties: (NSDictionary*)properties
                           error: (NSError**)outError
{
    return [_document putProperties: properties
                          prevRevID: _rev.revID
                              error: outError];
}


- (TouchRevision*) deleteDocument: (NSError**)outError {
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


- (TouchAttachment*) attachmentNamed: (NSString*)name {
    NSDictionary* metadata = [self attachmentMetadataFor: name];
    if (!metadata)
        return nil;
    return [[[TouchAttachment alloc] initWithRevision: self name: name metadata: metadata] autorelease];
}


- (NSArray*) attachments {
    return [self.attachmentNames my_map: ^(NSString* name) {
        return [self attachmentNamed: name];
    }];
}


@end
