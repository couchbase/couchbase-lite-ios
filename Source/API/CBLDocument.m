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
    BOOL _currentRevisionKnown;
    __weak id<CBLDocumentModel> _modelObject;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)docID
                           exists: (BOOL)exists
{
    self = [super init];
    if (self) {
        _database = database;
        _docID = [docID copy];
        _currentRevisionKnown = !exists;
    }
    return self;
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], self.abbreviatedID);
}


- (id) debugQuickLookObject {
    if (_currentRevision && _currentRevision.propertiesAreLoaded)
        return [CBLJSON stringWithJSONObject: _currentRevision.properties
                                     options:CBLJSONWritingPrettyPrinted error: NULL];
    else if (_currentRevisionKnown)
        return $sprintf(@"\"_id\":\"%@\"\n(doesn't exist yet)", _docID);
    else
        return $sprintf(@"\"_id\":\"%@\"\n(sorry, data not loaded)", _docID);
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
    CBLStatus status = [_database.storage purgeRevisions: @{self.documentID : @[@"*"]} result: nil];
    if (CBLStatusIsError(status)) {
        CBLStatusToOutNSError(status, outError);
        return NO;
    }
    [_database removeDocumentFromCache: self];
    return YES;
}


- (BOOL) isDeleted {
    CBLRevision *currentRev = self.currentRevision;
    return currentRev.isDeletion || ((currentRev == nil) && ([self getLeafRevisions: NULL].count > 0));
}


- (BOOL) isGone {
    return self.currentRevision.isGone;
}


- (NSDate*) expirationDate {
    UInt64 timestamp = [_database.storage expirationOfDocument: self.documentID];
    if (timestamp == 0)
        return nil;
    return [NSDate dateWithTimeIntervalSince1970: timestamp];
}

- (void) setExpirationDate: (NSDate*)date {
    [_database setExpirationDate: date ofDocument: self.documentID];
}


#pragma mark - REVISIONS:


- (CBLSavedRevision*) currentRevision {
    if (!_currentRevisionKnown) {
        CBLStatus status;
        _currentRevision =  [self revisionFromRev: [_database getDocumentWithID: _docID
                                                                     revisionID: nil
                                                                       withBody: YES
                                                                         status: &status]];
        if (_currentRevision || status == kCBLStatusNotFound || !CBLStatusIsError(status))
            _currentRevisionKnown = YES;
    }
    return _currentRevision;
}


- (void) forgetCurrentRevision {
    _currentRevisionKnown = NO;
    _currentRevision = nil;
}


- (NSString*) currentRevisionID {
    return self.currentRevision.revisionID;
}


- (CBLSavedRevision*) revisionFromRev: (CBL_Revision*)rev {
    if (!rev)
        return nil;
    else if ($equal(rev.revID, _currentRevision.rev.revID))
        return _currentRevision;
    else
        return [[CBLSavedRevision alloc] initWithDocument: self revision: rev];
}


- (CBLSavedRevision*) revisionWithID: (NSString*)revIDStr  {
    return [self revisionWithRevID: revIDStr.cbl_asRevID withBody: YES];
}


- (CBLSavedRevision*) revisionWithRevID: (CBL_RevID*)revID
                               withBody: (BOOL)withBody
{
    if (!revID)
        return nil;
    if ($equal(revID, _currentRevision.rev.revID))
        return _currentRevision;
    CBLStatus status;
    return [self revisionFromRev: [_database getDocumentWithID: _docID
                                                    revisionID: revID
                                                      withBody: withBody
                                                        status: &status]];
}


- (CBLUnsavedRevision*) newRevision {
    return [[CBLUnsavedRevision alloc] initWithDocument: self parent: self.currentRevision];
}


// Notification from the CBLDatabase that a (current, winning) revision has been added
- (void) revisionAdded: (CBLDatabaseChange*)change notify: (BOOL)notify {
    if (change.revisionID) {
        CBL_RevID* revID = change.winningRevisionID;
        if (!revID)
            return; // current revision didn't change
        if (_currentRevisionKnown && !$equal(revID, _currentRevision.rev.revID)) {
            CBL_Revision* rev = change.winningRevisionIfKnown;
            if (!rev)
                [self forgetCurrentRevision];
            else if (rev.deleted)
                _currentRevision = nil;
            else
                _currentRevision = [[CBLSavedRevision alloc] initWithDocument: self revision: rev];
        }
    } else {
        // Document was purged!
        _currentRevision = nil;
    }

    id<CBLDocumentModel> model = _modelObject; // strong reference to it
    [model document: self didChange: change];

    if (notify) {
        NSNotification* n = [NSNotification notificationWithName: kCBLDocumentChangeNotification
                                                          object: self
                                                        userInfo: @{@"change": change}];
        [[NSNotificationCenter defaultCenter] postNotification: n];
    }
}


- (void) loadCurrentRevisionFrom: (CBLQueryRow*)row {
    CBL_RevID* revID = row._documentRevisionID;
    if (!revID)
        return;
    if (!_currentRevision || [revID compare: _currentRevision.rev.revID] > 0) {
        [self forgetCurrentRevision];
        CBL_Revision* rev = row.documentRevision;
        if (rev) {
            _currentRevision = [[CBLSavedRevision alloc] initWithDocument: self revision: rev];
            _currentRevisionKnown = YES;
        }
    }
}


- (NSArray*) getRevisionHistory: (NSError**)outError {
    return [self.currentRevision getRevisionHistory: outError];
}


- (NSArray*) getLeafRevisions: (NSError**)outError includeDeleted: (BOOL)includeDeleted {
    CBL_RevisionList* revs = [_database.storage getAllRevisionsOfDocumentID: _docID
                                                                onlyCurrent: YES
                                                             includeDeleted: includeDeleted];
    return [revs.allRevisions my_map: ^CBLSavedRevision*(CBL_Revision* rev) {
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

- (NSMutableDictionary*) propertiesToInsert: (NSDictionary*)properties
                                      error: (NSError**)outError
{
    if (!properties)    // nil properties implies deletion
        return [NSMutableDictionary dictionaryWithObject: @YES forKey: @"_deleted"];

    id idProp = properties.cbl_id;
    if (idProp && ![idProp isEqual: self.documentID]) {
        Warn(@"Trying to PUT wrong _id to %@: %@", self, properties);
        CBLStatusToOutNSError(kCBLStatusBadRequest, outError);
        return nil;
    }

    NSMutableDictionary* nuProperties = [properties mutableCopy];

    // Process _attachments dict, converting CBLAttachments to dicts:
    NSDictionary* attachments = properties.cbl_attachments;
    if (attachments.count) {
        __block BOOL ok = YES;
        __block NSError* error;
        NSDictionary* expanded = [attachments my_dictionaryByUpdatingValues: ^id(NSString* name,
                                                                                 id value) {
            CBLAttachment* attachment = $castIf(CBLAttachment, value);
            if (ok && attachment) {
                ok = [attachment saveToDatabase: _database error: &error];
                value = attachment.metadata;
            }
            return value;
        }];

        if (!ok) {
            if (outError)
                *outError = error;
            return nil;
        }
        if (expanded != attachments)
            nuProperties[@"_attachments"] = expanded;
    }
    return nuProperties;
}

- (CBLSavedRevision*) putProperties: (NSDictionary*)properties
                          prevRevID: (CBL_RevID*)prevID
                      allowConflict: (BOOL)allowConflict
                              error: (NSError**)outError
{
    NSMutableDictionary* mProperties = [self propertiesToInsert: properties error: outError];
    if (!mProperties)
        return nil;
    CBLStatus status = 0;
    CBL_Revision* newRev = [_database putDocID: _docID
                                    properties: mProperties
                                prevRevisionID: prevID
                                 allowConflict: allowConflict
                                        source: nil
                                        status: &status
                                         error: outError];
    if (!newRev)
        return nil;
    
    return [self revisionFromRev: newRev];
}

- (CBLSavedRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError {
    CBL_RevID* prevID = properties.cbl_rev;
    return [self putProperties: properties prevRevID: prevID allowConflict: NO error: outError];
}

- (CBLSavedRevision*) update: (BOOL(^)(CBLUnsavedRevision*))block error: (NSError**)outError {
    NSError* error;
    do {
        // if there is a conflict error, get the latest revision from db instead of cache
        if (error)
            [self forgetCurrentRevision];
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

- (BOOL) putExistingRevisionWithProperties: (CBLJSONDict*)properties
                               attachments: (NSDictionary*)attachments
                           revisionHistory: (NSArray<NSString*>*)revIDStrings
                                   fromURL: (NSURL*)sourceURL
                                     error: (NSError**)outError
{
    Assert(revIDStrings.count > 0);
    NSMutableDictionary* mProperties = [self propertiesToInsert: properties error: outError];
    if (!mProperties)
        return NO;
    NSArray<CBL_RevID*>* revIDs = revIDStrings.cbl_asRevIDs;
    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: _docID
                                                                    revID: revIDs[0]
                                                                  deleted: properties.cbl_deleted];
    rev.properties = mProperties;
    if (![_database registerAttachmentBodies: attachments forRevision: rev error: outError])
        return NO;
    CBLStatus status = [_database forceInsert: rev
                              revisionHistory: revIDs
                                       source: sourceURL
                                        error: outError];
    return !CBLStatusIsError(status);
}

@end
