//
//  TDRouter.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TDDatabase.h>
@class TDServer, TDDatabaseManager, TDResponse, TDBody, TDMultipartWriter;


typedef TDStatus (^OnAccessCheckBlock)(TDDatabase*, NSString *docID, SEL action);
typedef void (^OnResponseReadyBlock)(TDResponse*);
typedef void (^OnDataAvailableBlock)(NSData* data, BOOL finished);
typedef void (^OnFinishedBlock)();


@interface TDRouter : NSObject
{
    @private
    TDServer* _server;
    TDDatabaseManager* _dbManager;
    NSURLRequest* _request;
    NSMutableArray* _path;
    NSDictionary* _queries;
    TDResponse* _response;
    TDDatabase* _db;
    BOOL _waiting;
    BOOL _responseSent;
    OnAccessCheckBlock _onAccessCheck;
    OnResponseReadyBlock _onResponseReady;
    OnDataAvailableBlock _onDataAvailable;
    OnFinishedBlock _onFinished;
    BOOL _running;
    BOOL _longpoll;
    TDFilterBlock _changesFilter;
    BOOL _changesIncludeDocs;
}

- (id) initWithServer: (TDServer*)server request: (NSURLRequest*)request;

@property (copy) OnAccessCheckBlock onAccessCheck;
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
@property (readonly) NSString* ifMatch;
- (TDStatus) openDB;
- (void) sendResponse;
- (void) finished;
@end



@interface TDResponse : NSObject
{
    @private
    TDStatus _internalStatus;
    int _status;
    NSString* _statusMsg;
    NSMutableDictionary* _headers;
    TDBody* _body;
}

@property (nonatomic) TDStatus internalStatus;
@property (nonatomic) int status;
@property (nonatomic, readonly) NSString* statusMsg;
@property (nonatomic, retain) NSMutableDictionary* headers;
@property (nonatomic, retain) TDBody* body;
@property (nonatomic, copy) id bodyObject;
@property (nonatomic, readonly) NSString* baseContentType;

- (void) reset;
- (void) setValue: (NSString*)value ofHeader: (NSString*)header;

- (void) setMultipartBody: (TDMultipartWriter*)mp;
- (void) setMultipartBody: (NSArray*)parts type: (NSString*)type;

@end