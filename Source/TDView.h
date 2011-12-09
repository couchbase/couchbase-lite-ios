//
//  TDView.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TDDatabase.h"


typedef void (^TDMapEmitBlock)(id key, id value);

/** A "map" function called when a document is to be added to a view.
    @param doc  The contents of the document being analyzed.
    @param emit  A block to be called to add a key/value pair to the view. Your block can call it zero, one or multiple times. */
typedef void (^TDMapBlock)(NSDictionary* doc, TDMapEmitBlock emit);


/** Standard query options for views. */
typedef struct TDQueryOptions {
    NSString* startKey;
    NSString* endKey;
    int skip;
    int limit;
    BOOL descending;
    BOOL includeDocs;
    BOOL updateSeq;
} TDQueryOptions;

extern const TDQueryOptions kDefaultTDQueryOptions;


/** Represents a view available in a database. */
@interface TDView : NSObject
{
    @private
    TDDatabase* _db;
    NSString* _name;
    int _viewID;
    TDMapBlock _mapBlock;
}

- (void) deleteView;

@property (readonly) TDDatabase* database;
@property (readonly) NSString* name;

@property (readonly) TDMapBlock mapBlock;
- (BOOL) setMapBlock: (TDMapBlock)mapBlock version: (NSString*)version;

- (void) removeIndex;
- (BOOL) updateIndex;

- (NSDictionary*) queryWithOptions: (const TDQueryOptions*)options;

@end
