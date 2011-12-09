//
//  ToyRev.h
//  ToyCouch
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ToyBody;


/** Database sequence ID */
typedef SInt64 SequenceNumber;


/** Stores information about a revision -- its docID, revID, and whether it's deleted. It can also store the sequence number and document contents (they can be added after creation). */
@interface ToyRev : NSObject
{
    @private
    NSString* _docID, *_revID;
    BOOL _deleted;
    ToyBody* _body;
    SInt64 _sequence;
}

- (id) initWithDocID: (NSString*)docID 
               revID: (NSString*)revID 
             deleted: (BOOL)deleted;
- (id) initWithBody: (ToyBody*)body;
- (id) initWithProperties: (NSDictionary*)properties;

@property (readonly) NSString* docID;
@property (readonly) NSString* revID;
@property (readonly) BOOL deleted;

@property (retain) ToyBody* body;
@property (copy) NSDictionary* properties;
@property (copy) NSData* asJSON;

@property SequenceNumber sequence;

- (ToyRev*) copyWithDocID: (NSString*)docID revID: (NSString*)revID;

@end



/** An ordered list of ToyRevs. */
@interface ToyRevList : NSObject <NSFastEnumeration>
{
    @private
    NSMutableArray* _revs;
}

@property (readonly) NSUInteger count;

- (ToyRev*) revWithDocID: (NSString*)docID revID: (NSString*)revID;

- (NSEnumerator*) objectEnumerator;

@property (readonly) NSArray* allDocIDs;
@property (readonly) NSArray* allRevIDs;

- (void) addRev: (ToyRev*)rev;
- (void) removeRev: (ToyRev*)rev;

@end
