//
//  CBLDocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDictionary.h"
@class CBLMutableDocument;

/** A Couchbase Lite document. The CBLDocument is immutable. */
@interface CBLDocument : NSObject <CBLDictionary>

/** The document's ID. */
@property (readonly, nonatomic) NSString* id;

/** Is the document deleted? */
@property (readonly, nonatomic) BOOL isDeleted;

/** 
 Sequence number of the document in the database.
 This indicates how recently the document has been changed: every time any document is updated,
 the database assigns it the next sequential sequence number. Thus, if a document's `sequence`
 property changes that means it's been changed (on-disk); and if one document's `sequence`
 is greater than another's, that means it was changed more recently.
 */
@property (readonly, nonatomic) uint64_t sequence;

/**
 Returns a mutable copy of the document.
 
 @return The CBLMutableDocument object.
 */
- (CBLMutableDocument*) toMutable;

- (instancetype) init NS_UNAVAILABLE;


@end
