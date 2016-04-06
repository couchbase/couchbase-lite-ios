//
//  CBL_Revision.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Revision.h"
#import "CBLInternal.h"
#import "CBL_Body.h"
#import "CBJSONEncoder.h"
#import "CBLMisc.h"


@implementation CBL_Revision
{
@protected
    CBL_Body* _body;
    NSString* _docID, *_revID;
    SequenceNumber _sequence;
    bool _deleted;
    bool _missing;
}

- (instancetype) initWithDocID: (UU NSString*)docID
                         revID: (UU NSString*)revID
                       deleted: (BOOL)deleted
{
    self = [super init];
    if (self) {
        if (!docID && (revID || deleted)) {
            // Illegal rev
            return nil;
        }
        _docID = docID.copy;
        _revID = revID.copy;
        _deleted = deleted;
    }
    return self;
}

- (instancetype) initWithDocID: (UU NSString*)docID
                         revID: (UU NSString*)revID
                       deleted: (BOOL)deleted
                          body: (UU CBL_Body*)body
{
    self = [super init];
    if (self) {
        if (!docID && (revID || deleted)) {
            // Illegal rev
            return nil;
        }
        _docID = docID.copy;
        _revID = revID.copy;
        _deleted = deleted;
        _body = body;

    }
    return self;
}

- (instancetype) initWithBody: (UU CBL_Body*)body {
    Assert(body);
    NSDictionary* props = body.properties;
    self = [self initWithDocID: props.cbl_id
                         revID: props.cbl_rev
                       deleted: props.cbl_deleted];
    if (self) {
        _body = body;
    }
    return self;
}

- (instancetype) initWithProperties: (UU NSDictionary*)properties {
    CBL_Body* body = [[CBL_Body alloc] initWithProperties: properties];
    if (!body) {
        return nil;
    }
    return [self initWithBody: body];
}

+ (instancetype) revisionWithProperties: (UU NSDictionary*)properties {
    return [[self alloc] initWithProperties: properties];
}


- (id) copyWithZone: (NSZone*)zone {
    return self; // I am immutable
}

- (id) mutableCopyWithZone: (NSZone*)zone {
    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: _docID
                                                                    revID: _revID
                                                                  deleted: _deleted];
    rev.body = _body;
    rev.sequence = _sequence;
    rev.missing = _missing;
    return rev;
}

- (CBL_Revision*) copyWithoutBody {
    if (!_body && self.class == [CBL_Revision class])
        return self;
    CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: _docID revID: _revID
                                                    deleted: _deleted];
    rev->_sequence = _sequence;
    rev->_missing = _missing;
    return rev;
}

@synthesize docID=_docID, revID=_revID, deleted=_deleted, missing=_missing, body=_body;

- (SequenceNumber) sequenceIfKnown {
    return _sequence;
}

- (SequenceNumber) sequence {
    Assert(_sequence, @"Sequence of %@ unknown", self);
    return _sequence;
}

- (void) setSequence:(SequenceNumber)sequence {
    if (sequence != _sequence) {
        Assert(_sequence == 0, @"Sequence has already been set");
        _sequence = sequence;
    }
}

- (void) forgetSequence {
    _sequence = 0;
}

- (unsigned) generation {
    return [[self class] generationFromRevID: _revID];
}

+ (unsigned) generationFromRevID: (UU NSString*)revID {
    unsigned generation = 0;
    NSUInteger length = MIN(revID.length, 9u);
    for (NSUInteger i=0; i<length; ++i) {
        unichar c = [revID characterAtIndex: i];
        if (isdigit(c))
            generation = 10*generation + digittoint(c);
        else if (c == '-')
            return generation;
        else
            break;
    }
    return 0;
}

// Splits a revision ID into its generation number and opaque suffix string
+ (BOOL) parseRevID: (UU NSString*)revID intoGeneration: (int*)outNum andSuffix:(NSString**)outSuffix
{
    NSScanner* scanner = [[NSScanner alloc] initWithString: revID];
    scanner.charactersToBeSkipped = nil;
    BOOL parsed = [scanner scanInt: outNum] && [scanner scanString: @"-" intoString: NULL];
    if (outSuffix)
        *outSuffix = [revID substringFromIndex: scanner.scanLocation];
    return parsed && *outNum > 0 && (!outSuffix || (*outSuffix).length > 0);
}


- (NSDictionary*) properties {
    return _body.properties;
}

- (id)objectForKeyedSubscript:(id)key {
    return [_body objectForKeyedSubscript: key];
}

- (NSDictionary*) attachments {
    return self.properties.cbl_attachments;
}

- (NSData*) asJSON {
    return _body.asJSON;
}

- (NSString*) description {
    return $sprintf(@"{%@ #%@%@}", _docID, _revID, (_deleted ?@" DEL" :@""));
}

- (BOOL) isEqual:(UU id)object {
    return [_docID isEqual: [object docID]] && [_revID isEqual: [object revID]];
}

- (NSUInteger) hash {
    return _docID.hash ^ _revID.hash;
}

- (NSComparisonResult) compareSequences: (UU CBL_Revision*)rev {
    NSParameterAssert(rev != nil);
    return CBLSequenceCompare(_sequence, rev->_sequence);
}

- (NSComparisonResult) compareSequencesDescending: (CBL_Revision*)rev {
    NSParameterAssert(rev != nil);
    return CBLSequenceCompare(_sequence, rev->_sequence) * -1;
}

- (CBL_MutableRevision*) mutableCopyWithDocID: (UU NSString*)docID revID: (UU NSString*)revID {
    CBL_MutableRevision* rev = [self mutableCopy];
    [rev setDocID: docID revID: revID];
    return rev;
}

- (CBL_Revision*) revisionByAddingBasicMetadata {
    NSMutableDictionary* props = [self.properties mutableCopy];
    if (!props)
        return nil; // failed to parse
    props[@"_id"] = self.docID;
    props[@"_rev"] = self.revID;
    if (_deleted)
        props[@"_deleted"] = @YES;
    CBL_Revision* result = [[CBL_Revision alloc] initWithProperties: props];
    result->_sequence = _sequence;
    return result;
}


- (NSData*) asCanonicalJSON {
    return [[self class] asCanonicalJSON: self.properties error: NULL];
}

/** Returns the JSON to be stored into the database.
    This has all the special keys like "_id" stripped out, and keys in canonical order. */
+ (NSData*) asCanonicalJSON: (UU NSDictionary*)properties error: (NSError**)outError {
    // Initialize the key filter that will strip out top level "_"-prefixed keys:
    static CBJSONEncoderKeyFilter sKeyFilter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSSet* specialKeysToRemove, *specialKeysToLeave;
        specialKeysToRemove = [[NSSet alloc] initWithObjects: @"_id", @"_rev",
                                       @"_deleted", @"_revisions", @"_revs_info", @"_conflicts",
                                       @"_deleted_conflicts", @"_local_seq", nil];
        specialKeysToLeave = [[NSSet alloc] initWithObjects:
                               @"_attachments", @"_removed", nil];
        sKeyFilter = ^BOOL(NSString* key, NSError** outError) {
            if (![key hasPrefix: @"_"]) {
                return YES;
            } else if ([specialKeysToRemove member: key]) {
                return NO;
            } else if ([specialKeysToLeave member: key]) {
                return YES;
            } else {
                Log(@"CBLDatabase: Invalid top-level key '%@' in document to be inserted", key);
                return CBLStatusToOutNSError(kCBLStatusBadJSON, outError);
            }
        };
    });

    if (!properties) {
        CBLStatusToOutNSError(kCBLStatusBadJSON, outError);
        return nil;
    }

    // Create canonical JSON -- this is important, because the JSON data returned here will be used
    // to create the new revision ID, and we need to guarantee that equivalent revision bodies
    // result in equal revision IDs.
    CBJSONEncoder* encoder = [[CBJSONEncoder alloc] init];
    encoder.canonical = YES;
    encoder.keyFilter = sKeyFilter;
    if (![encoder encode: properties]) {
        if (outError)
            *outError = encoder.error;
        return nil;
    }
    return encoder.encodedData;
}


@end



@implementation CBL_MutableRevision

@dynamic body, properties, asJSON, missing;     // Necessary because this class redeclares them

- (void) setBody:(UU CBL_Body *)body {
    _body = body;
}

- (void) setDocID:(UU NSString *)docID revID: (UU NSString*)revID {
    Assert(docID);

    if (_docID)
        Assert($equal(_docID, docID));
    else
        _docID = [docID copy];
    _revID = [revID copy];

    // Update the _id and _rev in the JSON, but only if those properties were already set:
    NSDictionary* properties = self.properties;
    if (properties) {
        NSString* idProp = properties.cbl_id, *revProp = properties.cbl_rev;
        if ((idProp && !$equal(idProp, _docID)) || (revProp && !$equal(revProp, revID))) {
            NSMutableDictionary* nuProperties = [properties mutableCopy];
            [nuProperties setValue: docID forKey: @"_id"];
            [nuProperties setValue: revID forKey: @"_rev"];
            self.properties = [nuProperties copy];
        }
    }
}

- (void) setProperties:(UU NSDictionary *)properties {
    _body = [[CBL_Body alloc] initWithProperties: properties];
}

- (void) setAsJSON:(UU NSData *)asJSON {
    _body = [[CBL_Body alloc] initWithJSON: asJSON
                               addingDocID: _docID revID: _revID deleted: _deleted];
}

- (void) setObject: (UU id)object forKeyedSubscript: (UU NSString*)key {
    NSMutableDictionary* nuProps = self.properties.mutableCopy;
    if (!nuProps)
        return; // failed to parse
    [nuProps setValue: object forKey: key];
    self.properties = nuProps;
}

- (void) setSequence:(SequenceNumber)sequence {
    _sequence = sequence;
}

- (void) setMissing:(bool)missing {
    _missing = missing;
}

- (id) copyWithZone: (NSZone*)zone {
    // Overridden because CBL_Revision just returns `self` instead of making a copy
    CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: _docID revID: _revID deleted: _deleted];
    rev->_body = _body;
    rev->_sequence = _sequence;
    rev->_missing = _missing;
    return rev;
}

// Calls the block on every attachment dictionary. The block can return a different dictionary,
// which will be replaced in the rev's properties. If it returns nil, the operation aborts.
// Returns YES if any changes were made.
- (BOOL) mutateAttachments: (NSDictionary*(^)(NSString*, NSDictionary*))block
{
    NSDictionary* properties = self.properties;
    if (!properties)
        return NO; // failed to parse
    NSMutableDictionary* editedProperties = nil;
    NSDictionary* attachments = (id)properties.cbl_attachments;
    NSMutableDictionary* editedAttachments = nil;
    for (NSString* name in attachments) {
        @autoreleasepool {
            NSDictionary* attachment = attachments[name];
            NSDictionary* editedAttachment = block(name, attachment);
            if (!editedAttachment) {
                return NO;  // block canceled
            }
            if (editedAttachment != attachment) {
                if (!editedProperties) {
                    // Make the document properties and _attachments dictionary mutable:
                    editedProperties = [properties mutableCopy];
                    editedAttachments = [attachments mutableCopy];
                    editedProperties[@"_attachments"] = editedAttachments;
                }
                editedAttachments[name] = editedAttachment;
            }
        }
    }
    if (editedProperties) {
        self.properties = editedProperties;
        return YES;
    }
    return NO;
}

@end



@implementation CBL_RevisionList
{
@private
    NSMutableArray* _revs;
}

- (instancetype) init {
    self = [super init];
    if (self) {
        _revs = [[NSMutableArray alloc] init];
    }
    return self;
}

- (instancetype) initWithArray: (NSArray*)revs {
    Assert(revs);
    self = [super init];
    if (self) {
        _revs = [revs mutableCopy];
    }
    return self;
}

- (instancetype) mutableCopyWithZone: (NSZone*)zoneIgnored {
    return [[[self class] alloc] initWithArray: _revs];
}


- (NSString*) description {
    return _revs.description;
}

- (NSUInteger) count {
    return _revs.count;
}

@synthesize allRevisions=_revs;

- (CBL_Revision*) objectAtIndexedSubscript: (NSUInteger)index {
    return _revs[index];
}

- (void) addRev: (CBL_Revision*)rev {
    [_revs addObject: rev];
}

- (void) removeRev: (CBL_Revision*)rev {
    [_revs removeObject: rev];
}

- (void) removeRevIdenticalTo: (CBL_Revision*)rev {
    [_revs removeObjectIdenticalTo: rev];
}

- (CBL_Revision*) removeAndReturnRev: (CBL_Revision*)rev {
    NSUInteger index = [_revs indexOfObject: rev];
    if (index == NSNotFound)
        return nil;
    rev = _revs[index];
    [_revs removeObjectAtIndex: index];
    return rev;
}

- (CBL_Revision*) revWithDocID: (NSString*)docID {
    for (CBL_Revision* rev in _revs) {
        if ($equal(rev.docID, docID))
            return rev;
    }
    return nil;
}

- (void) removeObjectAtIndex: (NSUInteger)index {
    [_revs removeObjectAtIndex: index];
}

- (CBL_Revision*) revWithDocID: (NSString*)docID revID: (NSString*)revID {
    for (CBL_Revision* rev in _revs) {
        if ($equal(rev.docID, docID) && $equal(rev.revID, revID))
            return rev;
    }
    return nil;
}

- (NSEnumerator*) objectEnumerator {
    return _revs.objectEnumerator;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len 
{
    return [_revs countByEnumeratingWithState: state objects: buffer count: len];
}

- (NSArray*) allDocIDs {
    return [_revs my_map: ^(id rev) {return [rev docID];}];
}

- (NSArray*) allRevIDs {
    return [_revs my_map: ^(id rev) {return [rev revID];}];
}

- (void) limit: (NSUInteger)limit {
    if (_revs.count > limit)
        [_revs removeObjectsInRange: NSMakeRange(limit, _revs.count - limit)];
}

- (void) sortBySequenceAscending:(BOOL)ascending {
    if (ascending)
        [_revs sortUsingSelector: @selector(compareSequences:)];
    else
        [_revs sortUsingSelector: @selector(compareSequencesDescending:)];
}

- (void) sortByDocID {
    [_revs sortUsingComparator: ^NSComparisonResult(CBL_Revision* r1, CBL_Revision* r2) {
        return [r1.docID compare: r2.docID];
    }];
}


@end



#pragma mark - COLLATE REVISION IDS:


static inline int sgn(int n) {
    return n>0 ? 1 : (n<0 ? -1 : 0);
}

static int defaultCollate(const char* str1, int len1, const char* str2, int len2) {
    int result = memcmp(str1, str2, MIN(len1, len2));
    return sgn(result ?: (len1 - len2));
}

static int parseDigits(const char* str, const char* end) {
    int result = 0;
    for (; str < end; ++str) {
        if (!isdigit(*str))
            return 0;
        result = 10*result + digittoint(*str);
    }
    return result;
}

/* A proper revision ID consists of a generation number, a hyphen, and an arbitrary suffix.
   Compare the generation numbers numerically, and then the suffixes lexicographically.
   If either string isn't a proper rev ID, fall back to lexicographic comparison. */
int CBLCollateRevIDs(void *context,
                    int len1, const void * chars1,
                    int len2, const void * chars2)
{
    const char *rev1 = chars1, *rev2 = chars2;
    const char* dash1 = memchr(rev1, '-', len1);
    const char* dash2 = memchr(rev2, '-', len2);
    if ((dash1==rev1+1 && dash2==rev2+1)
            || dash1 > rev1+8 || dash2 > rev2+8
            || dash1==NULL || dash2==NULL)
    {
        // Single-digit generation #s, or improper rev IDs; just compare as plain text:
        return defaultCollate(rev1,len1, rev2,len2);
    }
    // Parse generation numbers. If either is invalid, revert to default collation:
    int gen1 = parseDigits(rev1, dash1);
    int gen2 = parseDigits(rev2, dash2);
    if (!gen1 || !gen2)
        return defaultCollate(rev1,len1, rev2,len2);
    
    // Compare generation numbers; if they match, compare suffixes:
    return sgn(gen1 - gen2) ?: defaultCollate(dash1+1, len1-(int)(dash1+1-rev1),
                                              dash2+1, len2-(int)(dash2+1-rev2));
}


NSComparisonResult CBLCompareRevIDs(NSString* revID1, NSString* revID2) {
    CAssert(revID1 && revID2);
    const char* rev1str = [revID1 UTF8String];
    const char* rev2str = [revID2 UTF8String];
    return CBLCollateRevIDs(NULL, (int)strlen(rev1str), rev1str, (int)strlen(rev2str), rev2str);
}
