//
//  TDRouter.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
@class TDServer, TDResponse, TDBody;


typedef void (^OnResponseReadyBlock)(TDResponse*);
typedef void (^OnDataAvailableBlock)(NSData*);
typedef void (^OnFinishedBlock)();


@interface TDRouter : NSObject
{
    @private
    TDServer* _server;
    NSURLRequest* _request;
    NSMutableArray* _path;
    NSDictionary* _queries;
    TDResponse* _response;
    TDDatabase* _db;
    BOOL _waiting;
    BOOL _responseSent;
    OnResponseReadyBlock _onResponseReady;
    OnDataAvailableBlock _onDataAvailable;
    OnFinishedBlock _onFinished;
    BOOL _longpoll;
    TDFilterBlock _changesFilter;
    BOOL _changesIncludeDocs;
}

- (id) initWithServer: (TDServer*)server request: (NSURLRequest*)request;

@property (copy) OnResponseReadyBlock onResponseReady;
@property (copy) OnDataAvailableBlock onDataAvailable;
@property (copy) OnFinishedBlock onFinished;

@property (readonly) NSURLRequest* request;
@property (readonly) TDResponse* response;

- (void) start;
- (void) stop;

+ (NSString*) versionString;

@end


@interface TDRouter (Internal)
- (NSString*) query: (NSString*)param;
- (BOOL) boolQuery: (NSString*)param;
- (int) intQuery: (NSString*)param defaultValue: (int)defaultValue;
- (id) jsonQuery: (NSString*)param error: (NSError**)outError;
- (BOOL) cacheWithEtag: (NSString*)etag;
- (TDContentOptions) contentOptions;
- (BOOL) getQueryOptions: (struct TDQueryOptions*)options;
@property (readonly) NSString* multipartRequestType;
@property (readonly) NSDictionary* bodyAsDictionary;
- (TDStatus) openDB;
- (void) sendResponse;
@end



@interface TDResponse : NSObject
{
    @private
    int _status;
    NSMutableDictionary* _headers;
    TDBody* _body;
}

@property int status;
@property (retain) NSMutableDictionary* headers;
@property (retain) TDBody* body;
@property (copy) id bodyObject;
@property (readonly) NSString* baseContentType;

- (void) setValue: (NSString*)value ofHeader: (NSString*)header;

- (void) setMultipartBody: (NSArray*)parts type: (NSString*)type;

@end