//
//  TDDocument.m
//  TouchDB
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDBPrivate.h"
#import "TDDatabase+Insertion.h"
#import "TDRevision.h"


NSString* const kTouchDocumentChangeNotification = @"TouchDocumentChange";


@implementation TouchDocument


@synthesize owningCache=_owningCache;


- (id)initWithDatabase: (TouchDatabase*)database
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
    if (_modelObject)
        Warn(@"Deallocing %@ while it still has a modelObject %@", self, _modelObject);
    [_owningCache resourceBeingDealloced: self];
    [_currentRevision release];
    [_database release];
    [_docID release];
    [super dealloc];
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], self.abbreviatedID);
}


@synthesize database=_database, documentID=_docID, modelObject=_modelObject;


- (NSString*) abbreviatedID {
    NSMutableString* abbrev = [[self.documentID mutableCopy] autorelease];
    if (abbrev.length > 10)
        [abbrev replaceCharactersInRange: NSMakeRange(4, abbrev.length - 8) withString: @".."];
    return abbrev;
}


- (NSString*) cacheKey {
    return _docID;
}


- (BOOL) deleteDocument: (NSError**)outError {
    return [self.currentRevision deleteDocument: outError] != nil;
}


- (BOOL) isDeleted {
    return self.currentRevision.isDeleted;
}


#pragma mark - REVISIONS:


- (TouchRevision*) currentRevision {
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


- (TouchRevision*) revisionFromRev: (TDRevision*)rev {
    if (!rev)
        return nil;
    else if ($equal(rev.revID, _currentRevision.revisionID))
        return _currentRevision;
    else
        return [[[TouchRevision alloc] initWithDocument: self revision: rev] autorelease];
}


- (TouchRevision*) revisionWithID: (NSString*)revID  {
    return [self revisionFromRev: [_database.tddb getDocumentWithID: _docID revisionID: revID
                                                            options: 0
                                                             status: NULL]];
}


// Notification from the TouchDatabase that a (current) revision has been added to the database
- (void) revisionAdded: (TDRevision*)rev source: (NSURL*)source {
    if (_currentRevision && TDCompareRevIDs(rev.revID, _currentRevision.revisionID) > 0) {
        [_currentRevision autorelease];
        _currentRevision = [[TouchRevision alloc] initWithDocument: self revision: rev];
    }

    if ([_modelObject respondsToSelector: @selector(touchDocumentChanged:)])
        [_modelObject touchDocumentChanged: self];
    
    NSNotification* n = [NSNotification notificationWithName: kTouchDocumentChangeNotification
                                                      object: self
                                                    userInfo: nil];
    [[NSNotificationCenter defaultCenter] postNotification: n];
}


- (void) loadCurrentRevisionFrom: (TouchQueryRow*)row {
    NSString* revID = row.documentRevision;
    if (!revID)
        return;
    if (!_currentRevision || TDCompareRevIDs(revID, _currentRevision.revisionID) > 0) {
        [self forgetCurrentRevision];
        NSDictionary* properties = row.documentProperties;
        if (properties) {
            TDRevision* rev = [TDRevision revisionWithProperties: properties];
            _currentRevision = [[TouchRevision alloc] initWithDocument: self revision: rev];
        }
    }
}


- (NSArray*) getRevisionHistory: (NSError**)outError {
    return [self.currentRevision getRevisionHistory: outError];
}


- (NSArray*) getConflictingRevisions: (NSError**)outError {
    TDRevisionList* revs = [_database.tddb getAllRevisionsOfDocumentID: _docID onlyCurrent: YES];
    return [revs.allRevisions my_map: ^(TDRevision* rev) {
        return [self revisionFromRev: rev];
    }];
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

- (TouchRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError
{
    // Process _attachments dict, converting TouchAttachments to dicts:
    NSDictionary* attachments = [properties objectForKey: @"_attachments"];
    if (attachments.count) {
        NSDictionary* expanded = [TouchAttachment installAttachmentBodies: attachments
                                                             intoDatabase: _database];
        if (expanded != attachments) {
            NSMutableDictionary* nuProperties = [[properties mutableCopy] autorelease];
            [nuProperties setObject: expanded forKey: @"_attachments"];
            properties = nuProperties;
        }
    }
    
    BOOL deleted = !properties || [[properties objectForKey: @"_deleted"] boolValue];
    TDRevision* rev = [[[TDRevision alloc] initWithDocID: _docID
                                                   revID: nil
                                                 deleted: deleted] autorelease];
    if (properties)
        rev.properties = properties;
    TDStatus status = 0;
    rev = [_database.tddb putRevision: rev prevRevisionID: prevID allowConflict: NO status: &status];
    if (!rev) {
        if (outError) *outError = TDStatusToNSError(status, nil);
        return nil;
    }
    return [[[TouchRevision alloc] initWithDocument: self revision: rev] autorelease];
}

- (TouchRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError {
    NSString* prevID = [properties objectForKey: @"_rev"];
    return [self putProperties: properties prevRevID: prevID error: outError];
}


@end
