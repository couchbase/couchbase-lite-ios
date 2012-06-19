//
//  TDDatabase+Documents.h
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
@class TDQuery;


@interface TDDatabase (Documents)


/** Instantiates a TDDocument object with the given ID.
    Makes no server calls; a document with that ID doesn't even need to exist yet.
    TDDocuments are cached, so there will never be more than one instance (in this database)
    at a time with the same documentID. */
- (TDDocument*) documentWithID: (NSString*)docID;

/** Creates a TDDocument object with no current ID.
    The first time you PUT to that document, it will be created on the server (via a POST). */
- (TDDocument*) untitledDocument;

- (TDDocument*) cachedDocumentWithID: (NSString*)docID;

/** Empties the cache of recently used TDDocument objects.
    API calls will now instantiate and return new instances. */
- (void) clearDocumentCache;


@end
