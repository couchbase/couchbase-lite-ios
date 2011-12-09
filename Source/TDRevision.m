//
//  TDRev.m
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDRevision.h"
#import "TDBody.h"


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
    self = [self initWithDocID: [body propertyForKey: @"_id"] revID: nil deleted: NO];
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

- (void)dealloc {
    [_docID release];
    [_revID release];
    [_body release];
    [super dealloc];
}

@synthesize docID=_docID, revID=_revID, deleted=_deleted, body=_body, sequence=_sequence;

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

@end