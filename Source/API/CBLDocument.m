//
//  CBLDocument.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/4/12.
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
#import "CBLDatabaseChange.h"
#import "CBLInternal.h"


NSString* const kCBLDocumentChangeNotification = @"CBLDocumentChange";


@implementation CBLDocument
{
    CBLDatabase* _database;
    NSString* _docID;
    CBLSavedRevision* _currentRevision;
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
    CBLStatus status = [_database purgeRevisions: @{self.documentID : @[@"*"]} result: nil];
    if (CBLStatusIsError(status)) {
        if (outError)
            *outError = CBLStatusToNSError(status, nil);
        return NO;
    }
    [_database removeDocumentFromCache: self];
    return YES;
}


- (BOOL) isDeleted {
    return self.currentRevision.isDeletion;
}


- (BOOL) isGone {
    return self.currentRevision.isGone;
}


#pragma mark - REVISIONS:


- (CBLSavedRevision*) currentRevision {
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


- (CBLSavedRevision*) revisionFromRev: (CBL_Revision*)rev {
    if (!rev)
        return nil;
    else if ($equal(rev.revID, _currentRevision.revisionID))
        return _currentRevision;
    else
        return [[CBLSavedRevision alloc] initWithDocument: self revision: rev];
}


- (CBLSavedRevision*) revisionWithID: (NSString*)revID  {
    if (revID && $equal(revID, _currentRevision.revisionID))
        return _currentRevision;
    return [self revisionFromRev: [_database getDocumentWithID: _docID revisionID: revID
                                                       options: 0
                                                        status: NULL]];
}


- (CBLUnsavedRevision*) newRevision {
    return [[CBLUnsavedRevision alloc] initWithDocument: self parent: self.currentRevision];
}


// Notification from the CBLDatabase that a (current, winning) revision has been added
- (void) revisionAdded: (CBLDatabaseChange*)change {
    CBL_Revision* rev = change.winningRevision;
    if (!rev)
        return; // current revision didn't change
    if (_currentRevision && !$equal(rev.revID, _currentRevision.revisionID)) {
        _currentRevision = [[CBLSavedRevision alloc] initWithDocument: self revision: rev];
    }

    [_modelObject CBLDocument: self didChange: change];

    NSNotification* n = [NSNotification notificationWithName: kCBLDocumentChangeNotification
                                                      object: self
                                                    userInfo: @{@"change": change}];
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
            _currentRevision = [[CBLSavedRevision alloc] initWithDocument: self revision: rev];
        }
    }
}


- (NSArray*) getRevisionHistory: (NSError**)outError {
    return [self.currentRevision getRevisionHistory: outError];
}


- (NSArray*) getLeafRevisions: (NSError**)outError includeDeleted: (BOOL)includeDeleted {
    CBL_RevisionList* revs = [_database getAllRevisionsOfDocumentID: _docID onlyCurrent: YES];
    return [revs.allRevisions my_map: ^CBLSavedRevision*(CBL_Revision* rev) {
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

- (CBLSavedRevision*) putProperties: (NSDictionary*)properties
                          prevRevID: (NSString*)prevID
                      allowConflict: (BOOL)allowConflict
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
    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: _docID
                                                                    revID: nil
                                                                  deleted: deleted];
    if (properties)
        rev.properties = properties;
    CBLStatus status = 0;
    CBL_Revision* newRev = [_database putRevision: rev prevRevisionID: prevID
                                    allowConflict: allowConflict status: &status];
    if (!newRev) {
        if (outError) *outError = CBLStatusToNSError(status, nil);
        return nil;
    }
    return [self revisionFromRev: newRev];
}

- (CBLSavedRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError {
    NSString* prevID = properties[@"_rev"];
    return [self putProperties: properties prevRevID: prevID allowConflict: NO error: outError];
}

- (CBLSavedRevision*) update: (BOOL(^)(CBLUnsavedRevision*))block error: (NSError**)outError {
    NSError* error;
    do {
        CBLUnsavedRevision* newRev = self.newRevision;
        if (!block(newRev)) {
            error = nil;
            break; // cancel
        }
        CBLSavedRevision* savedRev = [newRev save: &error];
        if (savedRev)
            return savedRev; // success
    } while (CBLStatusFromNSError(error, 500) == kCBLStatusConflict);
    if (outError)
        *outError = error;
    return nil;
}

@end
