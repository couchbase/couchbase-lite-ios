//
//  TDRouter.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TD_Database.h>
@class TD_Server, TD_DatabaseManager, TDResponse, TD_Body, TDMultipartWriter;


typedef TDStatus (^OnAccessCheckBlock)(TD_Database*, NSString *docID, SEL action);
typedef void (^OnResponseReadyBlock)(TDResponse*);
typedef void (^OnDataAvailableBlock)(NSData* data, BOOL finished);
typedef void (^OnFinishedBlock)();


@interface TDRouter : NSObject
{
    @private
    TD_Server* _server;
    TD_DatabaseManager* _dbManager;
    NSURLRequest* _request;
    NSMutableArray* _path;
    NSDictionary* _queries;
    TDResponse* _response;
    TD_Database* _db;
    BOOL _local;
    BOOL _waiting;
    BOOL _responseSent;
    BOOL _processRanges;
    OnAccessCheckBlock _onAccessCheck;
    OnResponseReadyBlock _onResponseReady;
    OnDataAvailableBlock _onDataAvailable;
    OnFinishedBlock _onFinished;
    BOOL _running;
    BOOL _longpoll;
    TD_FilterBlock _changesFilter;
    NSDictionary* _changesFilterParams;
    BOOL _changesIncludeDocs;
    BOOL _changesIncludeConflicts;
}

- (id) initWithServer: (TD_Server*)server request: (NSURLRequest*)request isLocal: (BOOL)isLocal;

@property BOOL processRanges;

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
- (NSMutableDictionary*) jsonQueries;
- (BOOL) cacheWithEtag: (NSString*)etag;
- (TDContentOptions) contentOptions;
- (BOOL) getQueryOptions: (struct TDQueryOptions*)options;
@property (readonly) NSString* multipartRequestType;
@property (readonly) NSDictionary* bodyAsDictionary;
@property (readonly) NSString* ifMatch;
- (TDStatus) openDB;
- (void) sendResponseHeaders;
- (void) sendResponseBodyAndFinish: (BOOL)finished;
- (void) finished;
@end



@interface TDResponse : NSObject
{
    @private
    TDStatus _internalStatus;
    int _status;
    NSString* _statusMsg;
    NSString* _statusReason;
    NSMutableDictionary* _headers;
    TD_Body* _body;
}

@property (nonatomic) TDStatus internalStatus;
@property (nonatomic) int status;
@property (nonatomic, readonly) NSString* statusMsg;
@property (nonatomic, copy) NSString* statusReason;
@property (nonatomic, strong) NSMutableDictionary* headers;
@property (nonatomic, strong) TD_Body* body;
@property (nonatomic, copy) id bodyObject;
@property (nonatomic, readonly) NSString* baseContentType;

- (void) reset;
- (NSString*) objectForKeyedSubscript: (NSString*)header;
- (void) setObject: (NSString*)value forKeyedSubscript:(NSString*)header;

- (void) setMultipartBody: (TDMultipartWriter*)mp;
- (void) setMultipartBody: (NSArray*)parts type: (NSString*)type;

@end