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


typedef void (^OnResponseReadyBlock)(ToyResponse*);
typedef void (^OnDataAvailableBlock)(NSData*);
typedef void (^OnFinishedBlock)();


@interface ToyRouter : NSObject
{
    @private
    ToyServer* _server;
    NSURLRequest* _request;
    NSDictionary* _queries;
    ToyResponse* _response;
    ToyDB* _db;
    BOOL _waiting;
    BOOL _responseSent;
    OnResponseReadyBlock _onResponseReady;
    OnDataAvailableBlock _onDataAvailable;
    OnFinishedBlock _onFinished;
}

- (id) initWithServer: (ToyServer*)server request: (NSURLRequest*)request;

@property (copy) OnResponseReadyBlock onResponseReady;
@property (copy) OnDataAvailableBlock onDataAvailable;
@property (copy) OnFinishedBlock onFinished;

@property (readonly) ToyResponse* response;

- (void) start;
- (void) stop;

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