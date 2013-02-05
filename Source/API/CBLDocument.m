//
//  CBLDocument.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrivate.h"
#import "CBL_Database+Insertion.h"
#import "CBL_Revision.h"
#import "CBL_DatabaseChange.h"


NSString* const kCBLDocumentChangeNotification = @"CBLDocumentChange";


@implementation CBLDocument
{
    CBLDatabase* _database;
    NSString* _docID;
    CBLRevision* _currentRevision;
    __weak id _modelObject;
#if ! CBLCACHE_IS_SMART
    __weak CBLCache* _owningCache;
#endif
}


#if ! CBLCACHE_IS_SMART
@synthesize owningCache=_owningCache;
#endif


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)docID
{
    self = [super init];
    if (self) {
        _database = database;
        _docID = [docID copy];
    }
    return self;
}


#if ! CBLCACHE_IS_SMART
- (void)dealloc
{
    if (_modelObject)
        Warn(@"Deallocing %@ while it still has a modelObject %@", self, _modelObject);
    [_owningCache resourceBeingDealloced: self];
}
#endif


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], self.abbreviatedID);
}


@synthesize database=_database, documentID=_docID, modelObject=_modelObject;


- (NSString*) abbreviatedID {
    NSMutableString* abbrev = [self.documentID mutableCopy];
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


- (BOOL) purgeDocument: (NSError**)outError {
    CBLStatus status = [_database.tddb purgeRevisions: @{self.documentID : @"*"} result: nil];
    if (CBLStatusIsError(status)) {
        if (outError) {
            *outError = CBLStatusToNSError(status, nil);
            return NO;
        }
    }
    return YES;
}


- (BOOL) isDeleted {
    return self.currentRevision.isDeleted;
}


#pragma mark - REVISIONS:


- (CBLRevision*) currentRevision {
    if (!_currentRevision) {
        _currentRevision = [self revisionWithID: nil];
    }
    return _currentRevision;
}


- (void) forgetCurrentRevision {
    _currentRevision = nil;
}


- (NSString*) currentRevisionID {
    return self.currentRevision.revisionID;
}


- (CBLRevision*) revisionFromRev: (CBL_Revision*)rev {
    if (!rev)
        return nil;
    else if ($equal(rev.revID, _currentRevision.revisionID))
        return _currentRevision;
    else
        return [[CBLRevision alloc] initWithDocument: self revision: rev];
}


- (CBLRevision*) revisionWithID: (NSString*)revID  {
    if (revID && $equal(revID, _currentRevision.revisionID))
        return _currentRevision;
    return [self revisionFromRev: [_database.tddb getDocumentWithID: _docID revisionID: revID
                                                            options: 0
                                                             status: NULL]];
}


- (CBLNewRevision*) newRevision {
    return [[CBLNewRevision alloc] initWithDocument: self parent: self.currentRevision];
}


// Notification from the CBLDatabase that a (current, winning) revision has been added
- (void) revisionAdded: (CBL_DatabaseChange*)change {
    CBL_Revision* rev = change.winningRevision;
    if (_currentRevision && !$equal(rev.revID, _currentRevision.revisionID)) {
        _currentRevision = [[CBLRevision alloc] initWithDocument: self revision: rev];
    }

    if ([_modelObject respondsToSelector: @selector(tdDocumentChanged:)])
        [_modelObject tdDocumentChanged: self];
    
    NSNotification* n = [NSNotification notificationWithName: kCBLDocumentChangeNotification
                                                      object: self
                                                    userInfo: nil];
    [[NSNotificationCenter defaultCenter] postNotification: n];
}


- (void) loadCurrentRevisionFrom: (CBLQueryRow*)row {
    NSString* revID = row.documentRevision;
    if (!revID)
        return;
    if (!_currentRevision || CBLCompareRevIDs(revID, _currentRevision.revisionID) > 0) {
        [self forgetCurrentRevision];
        NSDictionary* properties = row.documentProperties;
        if (properties) {
            CBL_Revision* rev = [CBL_Revision revisionWithProperties: properties];
            _currentRevision = [[CBLRevision alloc] initWithDocument: self revision: rev];
        }
    }
}


- (NSArray*) getRevisionHistory: (NSError**)outError {
    return [self.currentRevision getRevisionHistory: outError];
}


- (NSArray*) getLeafRevisions: (NSError**)outError includeDeleted: (BOOL)includeDeleted {
    CBL_RevisionList* revs = [_database.tddb getAllRevisionsOfDocumentID: _docID onlyCurrent: YES];
    return [revs.allRevisions my_map: ^CBLRevision*(CBL_Revision* rev) {
        if (!includeDeleted && rev.deleted)
            return nil;
        return [self revisionFromRev: rev];
    }];
}

- (NSArray*) getConflictingRevisions: (NSError**)outError {
    return [self getLeafRevisions: outError includeDeleted: NO];
}


- (NSArray*) getLeafRevisions: (NSError**)outError {
    return [self getLeafRevisions: outError includeDeleted: YES];
}


#pragma mark - PROPERTIES:


- (NSDictionary*) properties {
    return self.currentRevision.properties;
}

- (id) propertyForKey: (NSString*)key {
    return (self.currentRevision.properties)[key];
}

- (id)objectForKeyedSubscript:(NSString*)key {
    return (self.currentRevision.properties)[key];
}

- (NSDictionary*) userProperties {
    return self.currentRevision.userProperties;
}

- (CBLRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError
{
    id idProp = [properties objectForKey: @"_id"];
    if (idProp && ![idProp isEqual: self.documentID])
        Warn(@"Trying to PUT wrong _id to %@: %@", self, properties);

    // Process _attachments dict, converting CBLAttachments to dicts:
    NSDictionary* attachments = properties[@"_attachments"];
    if (attachments.count) {
        NSDictionary* expanded = [CBLAttachment installAttachmentBodies: attachments
                                                             intoDatabase: _database];
        if (expanded != attachments) {
            NSMutableDictionary* nuProperties = [properties mutableCopy];
            nuProperties[@"_attachments"] = expanded;
            properties = nuProperties;
        }
    }
    
    BOOL deleted = !properties || [properties[@"_deleted"] boolValue];
    CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: _docID
                                                  revID: nil
                                                deleted: deleted];
    if (properties)
        rev.properties = properties;
    CBLStatus status = 0;
    rev = [_database.tddb putRevision: rev prevRevisionID: prevID allowConflict: NO status: &status];
    if (!rev) {
        if (outError) *outError = CBLStatusToNSError(status, nil);
        return nil;
    }
    return [[CBLRevision alloc] initWithDocument: self revision: rev];
}

- (CBLRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError {
    NSString* prevID = properties[@"_rev"];
    return [self putProperties: properties prevRevID: prevID error: outError];
}


@end
