//
//  TDDocument.m
//  TouchDB
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDocument.h"
#import "TDDocRevision.h"
#import "TDDatabase+Insertion.h"
#import "TDRevision.h"
#import "TDQuery.h"


@implementation TDDocument


@synthesize owningCache=_owningCache;


- (id)initWithDatabase: (TDDatabase*)database
            documentID: (NSString*)docID
{
    self = [super init];
    if (self) {
        _database = [database retain];
        _docID = [docID copy];
    }
    return self;
}


- (void)dealloc
{
    [_owningCache resourceBeingDealloced: self];
    [_currentRevision release];
    [_database release];
    [_docID release];
    [super dealloc];
}


@synthesize database=_database, documentID=_docID;


- (NSString*) cacheKey {
    return _docID;
}


#pragma mark - REVISIONS:


- (TDDocRevision*) currentRevision {
    if (!_currentRevision) {
        _currentRevision = [[self revisionWithID: nil] retain];
    }
    return _currentRevision;
}


- (void) forgetCurrentRevision {
    setObj(&_currentRevision, nil);
}


- (NSString*) currentRevisionID {
    return self.currentRevision.revisionID;
}


- (TDDocRevision*) revisionWithID: (NSString*)revID  {
    TDRevision* rev = [_database getDocumentWithID: _docID revisionID: revID options: 0];
    if (!rev)
        return nil;
    return [[[TDDocRevision alloc] initWithDocument: self revision: rev] autorelease];
}


// Notification from the TDDatabase that a (current) revision has been added to the database
- (void) revisionAdded: (TDRevision*)rev source: (NSURL*)source {
    if (_currentRevision && TDCompareRevIDs(rev.revID, _currentRevision.revisionID) > 0) {
        [_currentRevision autorelease];
        if (rev.deleted)
            _currentRevision = nil;
        else
            _currentRevision = [[TDDocRevision alloc] initWithDocument: self revision: rev];
    }
}


- (void) loadCurrentRevisionFrom: (TDQueryRow*)row {
    NSString* revID = row.documentRevision;
    if (!revID)
        return;
    if (!_currentRevision || TDCompareRevIDs(revID, _currentRevision.revisionID) > 0) {
        [self forgetCurrentRevision];
        NSDictionary* properties = row.documentProperties;
        if (properties) {
            TDRevision* rev = [TDRevision revisionWithProperties: properties];
            _currentRevision = [[TDDocRevision alloc] initWithDocument: self revision: rev];
        }
    }
}


#pragma mark - PROPERTIES:


- (NSDictionary*) properties {
    return self.currentRevision.properties;
}

- (id) propertyForKey: (NSString*)key {
    return [self.currentRevision.properties objectForKey: key];
}

- (NSDictionary*) userProperties {
    return self.currentRevision.userProperties;
}

- (TDDocRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError
{
    BOOL deleted = !properties || [[properties objectForKey: @"_deleted"] boolValue];
    TDRevision* rev = [[[TDRevision alloc] initWithDocID: _docID
                                                   revID: nil
                                                 deleted: deleted] autorelease];
    if (properties)
        rev.properties = properties;
    TDStatus status = 0;
    rev = [_database putRevision: rev prevRevisionID: prevID allowConflict: NO status: &status];
    if (!rev) {
        if (outError) *outError = TDStatusToNSError(status, nil);
        return nil;
    }
    return [[[TDDocRevision alloc] initWithDocument: self revision: rev] autorelease];
}

- (TDDocRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError {
    NSString* prevID = [properties objectForKey: @"_rev"];
    return [self putProperties: properties prevRevID: prevID error: outError];
}


@end
