//
//  CBLView.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrivate.h"
#import "CBL_View.h"


@implementation CBLView
{
@private
    CBLDatabase* _database;
    CBL_View* _view;
}


- (id)initWithDatabase: (CBLDatabase*)database view: (CBL_View*)view {
    self = [super init];
    if (self) {
        _database = database;
        _view = view;
    }
    return self;
}


- (NSString*) name {
    return _view.name;
}


@synthesize database=_database;


- (CBLMapBlock) mapBlock         {return _view.mapBlock;}
- (CBLReduceBlock) reduceBlock   {return _view.reduceBlock;}

- (BOOL) setMapBlock: (CBLMapBlock)mapBlock
         reduceBlock: (CBLReduceBlock)reduceBlock
             version: (NSString*)version
{
    if (mapBlock) {
        return [_view setMapBlock: mapBlock reduceBlock: reduceBlock version: version];
    } else {
        [_view deleteView];
        _view = nil;
        _database = nil;
        return YES;
    }
}

- (BOOL) setMapBlock: (CBLMapBlock)mapBlock
             version: (NSString*)version
{
    return [self setMapBlock: mapBlock reduceBlock: nil version: version];
}

- (CBLQuery*) query {
    return [[CBLQuery alloc] initWithDatabase: _database view: _view];
}


static id<CBLViewCompiler> sCompiler;


+ (void) setCompiler: (id<CBLViewCompiler>)compiler {
    sCompiler = compiler;
}

+ (id<CBLViewCompiler>) compiler {
    return sCompiler;
}


@end
