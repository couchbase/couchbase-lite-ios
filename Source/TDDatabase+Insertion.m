//
//  TDDatabase+Insertion.m
//  TouchDB
//
//  Created by Jens Alfke on 12/27/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDDatabase.h"
#import "TDRevision.h"
#import "TDInternal.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"


NSString* const TDDatabaseChangeNotification = @"TDDatabaseChange";


@interface TDValidationContext : NSObject <TDValidationContext>
{
    @private
    TDDatabase* _db;
    TDRevision* _currentRevision;
    TDStatus _errorType;
    NSString* _errorMessage;
}
- (id) initWithDatabase: (TDDatabase*)db revision: (TDRevision*)currentRevision;
@property (readonly) TDRevision* currentRevision;
@property TDStatus errorType;
@property (copy) NSString* errorMessage;
@end


@interface TDDatabase (Insertion_Internal)
- (TDStatus) validateRevision: (TDRevision*)newRev previousRevision: (TDRevision*)oldRev;
@end




@implementation TDDatabase (Insertion)


+ (BOOL) isValidDocumentID: (NSString*)str {
    // http://wiki.apache.org/couchdb/HTTP_Document_API#Documents
    return (str.length > 0);
}


static NSString* createUUID() {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString* str = NSMakeCollectable(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    return [str autorelease];
}

+ (NSString*) generateDocumentID {
    return createUUID();
}

- (NSString*) generateNextRevisionID: (NSString*)revID {
    // Revision IDs have a generation count, a hyphen, and a UUID.
    unsigned generation = 0;
    if (revID) {
        generation = [TDRevision generationFromRevID: revID];
        if (generation == 0)
            return nil;
    }
    NSString* digest = createUUID();  //TODO: Generate canonical digest of body
    return [NSString stringWithFormat: @"%u-%@", generation+1, digest];
}


- (void) notifyChange: (TDRevision*)rev source: (NSURL*)source
{
    NSDictionary* userInfo = $dict({@"rev", rev},
                                   {@"seq", $object(rev.sequence)},
                                   {@"source", source});
    [[NSNotificationCenter defaultCenter] postNotificationName: TDDatabaseChangeNotification
                                                        object: self
                                                      userInfo: userInfo];
}


- (SInt64) insertDocumentID: (NSString*)docID {
    if (![_fmdb executeUpdate: @"INSERT INTO docs (docid) VALUES (?)", docID])
        return -1;
    return _fmdb.lastInsertRowId;
}

- (SInt64) getOrInsertDocNumericID: (NSString*)docID {
    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID == 0)
        docNumericID = [self insertDocumentID: docID];
    return docNumericID;
}


- (NSData*) encodeDocumentJSON: (TDRevision*)rev {
    static NSSet* sKnownSpecialKeys;
    if (!sKnownSpecialKeys) {
        sKnownSpecialKeys = [[NSSet alloc] initWithObjects: @"_id", @"_rev",
                                         @"_attachments", @"_deleted", nil];
    }

    NSDictionary* origProps = rev.properties;
    if (!origProps)
        return nil;
    
    // Don't allow any "_"-prefixed keys. Known ones we'll ignore, unknown ones are an error.
    NSMutableDictionary* properties = [[NSMutableDictionary alloc] initWithCapacity: origProps.count];
    for (NSString* key in origProps) {
        if ([key hasPrefix: @"_"]) {
            if (![sKnownSpecialKeys member: key]) {
                Log(@"TDDatabase: Invalid top-level key '%@' in document to be inserted", key);
                [properties release];
                return nil;
            }
        } else {
            [properties setObject: [origProps objectForKey: key] forKey: key];
        }
    }
    
    NSError* error;
    NSData* json = [NSJSONSerialization dataWithJSONObject: properties options:0 error: &error];
    [properties release];
    Assert(json, @"Unable to serialize %@ to JSON: %@", rev, error);
    return json;
}


// Raw row insertion. Returns new sequence, or 0 on error
- (SequenceNumber) insertRevision: (TDRevision*)rev
                     docNumericID: (SInt64)docNumericID
                   parentSequence: (SequenceNumber)parentSequence
                          current: (BOOL)current
                             JSON: (NSData*)json
{
    if (![_fmdb executeUpdate: @"INSERT INTO revs (doc_id, revid, parent, current, deleted, json) "
                                "VALUES (?, ?, ?, ?, ?, ?)",
                               $object(docNumericID),
                               rev.revID,
                               (parentSequence ? $object(parentSequence) : nil ),
                               $object(current),
                               $object(rev.deleted),
                               json])
        return 0;
    return rev.sequence = _fmdb.lastInsertRowId;
}


- (TDRevision*) putRevision: (TDRevision*)rev
             prevRevisionID: (NSString*)prevRevID   // rev ID being replaced, or nil if an insert
                     status: (TDStatus*)outStatus
{
    Assert(!rev.revID);
    Assert(outStatus);
    NSString* docID = rev.docID;
    SInt64 docNumericID;
    BOOL deleted = rev.deleted;
    if (!rev || (prevRevID && !docID) || (deleted && !docID)) {
        *outStatus = 400;
        return nil;
    }
    
    *outStatus = 500;
    [self beginTransaction];
    FMResultSet* r = nil;
    @try {
        SequenceNumber parentSequence = 0;
        if (prevRevID) {
            // Replacing: make sure given prevRevID is current & find its sequence number:
            docNumericID = [self getOrInsertDocNumericID: docID];
            if (docNumericID <= 0)
                return nil;
            parentSequence = [_fmdb longLongForQuery: @"SELECT sequence FROM revs "
                                                "WHERE doc_id=? AND revid=? and current=1 LIMIT 1",
                                                 $object(docNumericID), prevRevID];
            if (parentSequence == 0) {
                // Not found: 404 or a 409, depending on whether there is any current revision
                *outStatus = [self existsDocumentWithID: docID revisionID: nil] ? 409 : 404;
                return nil;
            }
            
            if (_validations.count > 0) {
                // Fetch the previous revision and validate the new one against it:
                TDRevision* prevRev = [[TDRevision alloc] initWithDocID: docID revID: prevRevID
                                                                deleted: NO];
                TDStatus status = [self validateRevision: rev previousRevision: prevRev];
                [prevRev release];
                if (status >= 300) {
                    *outStatus = status;
                    return nil;
                }
            }
            
            // Make replaced rev non-current:
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                                       $object(parentSequence)])
                return nil;
        } else if (docID) {
            if (deleted) {
                // Didn't specify a revision to delete: 404 or a 409, depending
                *outStatus = [self existsDocumentWithID: docID revisionID: nil] ? 409 : 404;
                return nil;
            }
            // Inserting first revision, with docID given: make sure docID doesn't exist,
            // or exists but is currently deleted
            if (![self validateRevision: rev previousRevision: nil]) {
                *outStatus = 403;
                return nil;
            }
            docNumericID = [self getOrInsertDocNumericID: docID];
            if (docNumericID <= 0)
                return nil;
            r = [_fmdb executeQuery: @"SELECT sequence, deleted FROM revs "
                                      "WHERE doc_id=? and current=1 ORDER BY revid DESC LIMIT 1",
                                     $object(docNumericID)];
            if (!r)
                return nil;
            if ([r next]) {
                if ([r boolForColumnIndex: 1]) {
                    // Make the deleted revision no longer current:
                    if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                                               $object([r longLongIntForColumnIndex: 0])])
                        return nil;
                } else {
                    *outStatus = 409;
                    return nil;
                }
            }
            [r close];
            r = nil;
        } else {
            // Inserting first revision, with no docID given: generate a unique docID:
            docID = [[self class] generateDocumentID];
            docNumericID = [self insertDocumentID: docID];
            if (docNumericID <= 0)
                return nil;
        }
        
        // Bump the revID and update the JSON:
        NSString* newRevID = [self generateNextRevisionID: prevRevID];
        NSData* json = nil;
        if (!rev.deleted) {
            json = [self encodeDocumentJSON: rev];
            if (!json) {
                *outStatus = 400;  // bad or missing JSON
                return nil;
            }
        }
        rev = [[rev copyWithDocID: docID revID: newRevID] autorelease];
        
        // Now insert the rev itself:
        SequenceNumber sequence = [self insertRevision: rev
                                          docNumericID: docNumericID
                                        parentSequence: parentSequence
                                               current: YES
                                                  JSON: json];
        if (!sequence)
            return nil;
        
        // Store any attachments:
        TDStatus status = [self processAttachmentsForRevision: rev
                                           withParentSequence: parentSequence];
        if (status >= 300) {
            *outStatus = status;
            return nil;
        }
        
        // Success!
        *outStatus = deleted ? 200 : 201;
        
    } @finally {
        // Remember, we could have gotten here via a 'return' inside the @try block above.
        [r close];
        [self endTransaction: (*outStatus < 300)];
    }
    
    if (*outStatus >= 300) 
        return nil;
    
    // Send a change notification:
    [self notifyChange: rev source: nil];
    return rev;
}


- (TDStatus) forceInsert: (TDRevision*)rev
         revisionHistory: (NSArray*)history  // in *reverse* order, starting with rev's revID
                  source: (NSURL*)source
{
    BOOL success = NO;
    [self beginTransaction];
    @try {
        // First look up all locally-known revisions of this document:
        NSString* docID = rev.docID;
        SInt64 docNumericID = [self getOrInsertDocNumericID: docID];
        TDRevisionList* localRevs = [self getAllRevisionsOfDocumentID: docID
                                                            numericID: docNumericID
                                                          onlyCurrent: NO];
        if (!localRevs)
            return 500;
        NSUInteger historyCount = history.count;
        Assert(historyCount >= 1);
        
        // Validate against the latest common ancestor:
        if (_validations.count > 0) {
            TDRevision* oldRev = nil;
            for (NSUInteger i = 1; i<historyCount; ++i) {
                oldRev = [localRevs revWithDocID: docID revID: [history objectAtIndex: i]];
                if (oldRev)
                    break;
            }
            TDStatus status = [self validateRevision: rev previousRevision: oldRev];
            if (status >= 300)
                return status;
        }
        
        // Walk through the remote history in chronological order, matching each revision ID to
        // a local revision. When the list diverges, start creating blank local revisions to fill
        // in the local history:
        SequenceNumber sequence = 0;
        SequenceNumber localParentSequence = 0;
        for (NSInteger i = historyCount - 1; i>=0; --i) {
            NSString* revID = [history objectAtIndex: i];
            TDRevision* localRev = [localRevs revWithDocID: docID revID: revID];
            if (localRev) {
                // This revision is known locally. Remember its sequence as the parent of the next one:
                sequence = localRev.sequence;
                Assert(sequence > 0);
                localParentSequence = sequence;
                
            } else {
                // This revision isn't known, so add it:
                TDRevision* newRev;
                NSData* json = nil;
                BOOL current = NO;
                if (i==0) {
                    // Hey, this is the leaf revision we're inserting:
                    newRev = rev;
                    if (!rev.deleted) {
                        json = [self encodeDocumentJSON: rev];
                        if (!json)
                            return 400;
                    }
                    current = YES;
                } else {
                    // It's an intermediate parent, so insert a stub:
                    newRev = [[[TDRevision alloc] initWithDocID: docID revID: revID deleted: NO]
                                    autorelease];
                }

                // Insert it:
                sequence = [self insertRevision: newRev
                                   docNumericID: docNumericID
                                 parentSequence: sequence
                                        current: current 
                                           JSON: json];
                if (sequence <= 0)
                    return 500;
                newRev.sequence = sequence;
                
                if (i==0) {
                    // Write any changed attachments for the new revision. As the parent sequence use
                    // the latest local revision (this is to copy attachments from):
                    TDStatus status = [self processAttachmentsForRevision: rev
                                                       withParentSequence: localParentSequence];
                    if (status >= 300) 
                        return status;
                }
            }
        }

        // Mark the latest local rev as no longer current:
        if (localParentSequence > 0 && localParentSequence != sequence) {
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                  $object(localParentSequence)])
                return 500;
        }

        success = YES;
    } @finally {
        [self endTransaction: success];
    }
    
    // Notify and return:
    [self notifyChange: rev source: source];
    return 201;
}


- (void) addValidation:(TDValidationBlock)validationBlock {
    Assert(validationBlock);
    if (!_validations)
        _validations = [[NSMutableArray alloc] init];
    id copiedBlock = [validationBlock copy];
    [_validations addObject: copiedBlock];
    [copiedBlock release];
}


- (TDStatus) validateRevision: (TDRevision*)newRev previousRevision: (TDRevision*)oldRev {
    if (_validations.count == 0)
        return 200;
    TDValidationContext* context = [[TDValidationContext alloc] initWithDatabase: self
                                                                        revision: oldRev];
    TDStatus status = 200;
    for (TDValidationBlock validation in _validations) {
        if (!validation(newRev, context)) {
            status = context.errorType;
            break;
        }
    }
    [context release];
    return status;
}


@end






@implementation TDValidationContext

- (id) initWithDatabase: (TDDatabase*)db revision: (TDRevision*)currentRevision {
    self = [super init];
    if (self) {
        _db = db;
        _currentRevision = currentRevision;
        _errorType = 403;
        _errorMessage = [@"invalid document" retain];
    }
    return self;
}

- (void)dealloc {
    [_errorMessage release];
    [super dealloc];
}

- (TDRevision*) currentRevision {
    if (_currentRevision)
        [_db loadRevisionBody: _currentRevision withAttachments: NO];
    return _currentRevision;
}

@synthesize errorType=_errorType, errorMessage=_errorMessage;

@end
