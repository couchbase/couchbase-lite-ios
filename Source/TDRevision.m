//
//  TDRevision.m
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import <TouchDB/TDRevision.h>
#import "TDBody.h"
#import "TDMisc.h"


@implementation TDRevision

- (id) initWithDocID: (NSString*)docID 
               revID: (NSString*)revID 
             deleted: (BOOL)deleted
{
    self = [super init];
    if (self) {
        if (!docID && (revID || deleted)) {
            // Illegal rev
            [self release];
            return nil;
        }
        _docID = docID.copy;
        _revID = revID.copy;
        _deleted = deleted;
    }
    return self;
}

- (id) initWithBody: (TDBody*)body {
    Assert(body);
    self = [self initWithDocID: [body propertyForKey: @"_id"]
                         revID: [body propertyForKey: @"_rev"]
                       deleted: [body propertyForKey: @"_deleted"] == $true];
    if (self) {
        self.body = body;
    }
    return self;
}

- (id) initWithProperties: (NSDictionary*)properties {
    TDBody* body = [[[TDBody alloc] initWithProperties: properties] autorelease];
    if (!body) {
        [self release];
        return nil;
    }
    return [self initWithBody: body];
}

+ (TDRevision*) revisionWithProperties: (NSDictionary*)properties {
    return [[[self alloc] initWithProperties: properties] autorelease];
}

- (void)dealloc {
    [_docID release];
    [_revID release];
    [_body release];
    [super dealloc];
}

@synthesize docID=_docID, revID=_revID, deleted=_deleted, body=_body, sequence=_sequence;

- (unsigned) generation {
    return [[self class] generationFromRevID: _revID];
}

+ (unsigned) generationFromRevID: (NSString*)revID {
    unsigned generation = 0;
    NSUInteger length = revID.length;
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
+ (BOOL) parseRevID: (NSString*)revID intoGeneration: (int*)outNum andSuffix:(NSString**)outSuffix
{
    NSScanner* scanner = [[NSScanner alloc] initWithString: revID];
    scanner.charactersToBeSkipped = nil;
    BOOL parsed = [scanner scanInt: outNum] && [scanner scanString: @"-" intoString: NULL];
    if (outSuffix)
        *outSuffix = [revID substringFromIndex: scanner.scanLocation];
    [scanner release];
    return parsed && *outNum > 0 && (!outSuffix || (*outSuffix).length > 0);
}


- (NSDictionary*) properties {
    return _body.properties;
}

- (void) setProperties:(NSDictionary *)properties {
    self.body = [TDBody bodyWithProperties: properties];
}

- (NSData*) asJSON {
    return _body.asJSON;
}

- (void) setAsJSON:(NSData *)asJSON {
    self.body = [TDBody bodyWithJSON: asJSON];
}

- (NSString*) description {
    return $sprintf(@"{%@ #%@%@}", _docID, _revID, (_deleted ?@" DEL" :@""));
}

- (BOOL) isEqual:(id)object {
    return [_docID isEqual: [object docID]] && [_revID isEqual: [object revID]];
}

- (NSUInteger) hash {
    return _docID.hash ^ _revID.hash;
}

- (NSComparisonResult) compareSequences: (TDRevision*)rev {
    NSParameterAssert(rev != nil);
    return TDSequenceCompare(_sequence, rev->_sequence);
}

- (TDRevision*) copyWithDocID: (NSString*)docID revID: (NSString*)revID {
    Assert(docID && revID);
    Assert(!_docID || $equal(_docID, docID));
    TDRevision* rev = [[[self class] alloc] initWithDocID: docID revID: revID deleted: _deleted];
    if ( _body)
        rev.body = _body;
    return rev;
}


@end



@implementation TDRevisionList

- (id)init {
    self = [super init];
    if (self) {
        _revs = [[NSMutableArray alloc] init];
    }
    return self;
}

- (id) initWithArray: (NSArray*)revs {
    Assert(revs);
    self = [super init];
    if (self) {
        _revs = [revs mutableCopy];
    }
    return self;
}

- (void)dealloc {
    [_revs release];
    [super dealloc];
}

- (NSString*) description {
    return _revs.description;
}

- (NSUInteger) count {
    return _revs.count;
}

@synthesize allRevisions=_revs;

- (void) addRev: (TDRevision*)rev {
    [_revs addObject: rev];
}

- (void) removeRev: (TDRevision*)rev {
    [_revs removeObject: rev];
}

- (TDRevision*) revWithDocID: (NSString*)docID revID: (NSString*)revID {
    for (TDRevision* rev in _revs) {
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

- (void) sortBySequence {
    [_revs sortUsingSelector: @selector(compareSequences:)];
}


@end