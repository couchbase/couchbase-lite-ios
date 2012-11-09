//
//  TouchView.m
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDBPrivate.h"
#import "TD_View.h"


@implementation TDView
{
@private
    TDDatabase* _database;
    TD_View* _view;
}


- (id)initWithDatabase: (TDDatabase*)database view: (TD_View*)view {
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


- (TDMapBlock) mapBlock         {return _view.mapBlock;}
- (TDReduceBlock) reduceBlock   {return _view.reduceBlock;}

- (BOOL) setMapBlock: (TDMapBlock)mapBlock
         reduceBlock: (TDReduceBlock)reduceBlock
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

- (BOOL) setMapBlock: (TDMapBlock)mapBlock
             version: (NSString*)version
{
    return [self setMapBlock: mapBlock reduceBlock: nil version: version];
}

- (TDQuery*) query {
    return [[TDQuery alloc] initWithDatabase: _database view: _view];
}


@end
