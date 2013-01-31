//
//  CBL_Router.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "CBL_Database.h"
@class CBL_Server, CBL_DatabaseManager, CBLResponse, CBL_Body, CBLMultipartWriter;


typedef CBLStatus (^OnAccessCheckBlock)(CBL_Database*, NSString *docID, SEL action);
typedef void (^OnResponseReadyBlock)(CBLResponse*);
typedef void (^OnDataAvailableBlock)(NSData* data, BOOL finished);
typedef void (^OnFinishedBlock)();


@interface CBL_Router : NSObject
{
    @private
    CBL_Server* _server;
    CBL_DatabaseManager* _dbManager;
    NSURLRequest* _request;
    NSMutableArray* _path;
    NSDictionary* _queries;
    CBLResponse* _response;
    CBL_Database* _db;
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
    CBL_FilterBlock _changesFilter;
    NSDictionary* _changesFilterParams;
    BOOL _changesIncludeDocs;
    BOOL _changesIncludeConflicts;
}

- (id) initWithServer: (CBL_Server*)server request: (NSURLRequest*)request isLocal: (BOOL)isLocal;

@property BOOL processRanges;

@property (copy) OnAccessCheckBlock onAccessCheck;
@property (copy) OnResponseReadyBlock onResponseReady;
@property (copy) OnDataAvailableBlock onDataAvailable;
@property (copy) OnFinishedBlock onFinished;

@property (readonly) NSURLRequest* request;
@property (readonly) CBLResponse* response;

- (void) start;
- (void) stop;

@end


@interface CBL_Router (Internal)
- (NSString*) query: (NSString*)param;
- (BOOL) boolQuery: (NSString*)param;
- (int) intQuery: (NSString*)param defaultValue: (int)defaultValue;
- (id) jsonQuery: (NSString*)param error: (NSError**)outError;
- (NSMutableDictionary*) jsonQueries;
- (BOOL) cacheWithEtag: (NSString*)etag;
- (CBLContentOptions) contentOptions;
- (BOOL) getQueryOptions: (struct CBLQueryOptions*)options;
@property (readonly) NSString* multipartRequestType;
@property (readonly) NSDictionary* bodyAsDictionary;
@property (readonly) NSString* ifMatch;
- (CBLStatus) openDB;
- (void) sendResponseHeaders;
- (void) sendResponseBodyAndFinish: (BOOL)finished;
- (void) finished;
@end



@interface CBLResponse : NSObject
{
    @private
    CBLStatus _internalStatus;
    int _status;
    NSString* _statusMsg;
    NSString* _statusReason;
    NSMutableDictionary* _headers;
    CBL_Body* _body;
}

@property (nonatomic) CBLStatus internalStatus;
@property (nonatomic) int status;
@property (nonatomic, readonly) NSString* statusMsg;
@property (nonatomic, copy) NSString* statusReason;
@property (nonatomic, strong) NSMutableDictionary* headers;
@property (nonatomic, strong) CBL_Body* body;
@property (nonatomic, copy) id bodyObject;
@property (nonatomic, readonly) NSString* baseContentType;

- (void) reset;
- (NSString*) objectForKeyedSubscript: (NSString*)header;
- (void) setObject: (NSString*)value forKeyedSubscript:(NSString*)header;

- (void) setMultipartBody: (CBLMultipartWriter*)mp;
- (void) setMultipartBody: (NSArray*)parts type: (NSString*)type;

@end
