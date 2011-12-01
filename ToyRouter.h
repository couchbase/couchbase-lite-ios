//
//  ToyRouter.h
//  ToyCouch
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ToyDB, ToyServer, ToyResponse, ToyDocument;


extern NSString* const kToyVersionString;


@interface ToyRouter : NSObject
{
    @private
    ToyServer* _server;
    NSURLRequest* _request;
    NSDictionary* _queries;
    ToyResponse* _response;
    ToyDB* _db;
}

- (id) initWithServer: (ToyServer*)server request: (NSURLRequest*)request;

@property (readonly) ToyResponse* response;

@end



@interface ToyResponse : NSObject
{
    @private
    int _status;
    NSMutableDictionary* _headers;
    ToyDocument* _body;
}

@property int status;
@property (copy) NSMutableDictionary* headers;
@property (retain) ToyDocument* body;
@property (copy) id bodyObject;

- (void) setValue: (NSString*)value ofHeader: (NSString*)header;

@end