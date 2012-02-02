//
//  TDRemoteRequest.h
//  TouchDB
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef void (^TDRemoteRequestCompletionBlock)(id, NSError*);


@interface TDRemoteRequest : NSObject <NSURLConnectionDelegate
#if TARGET_OS_IPHONE
                                                              , NSURLConnectionDataDelegate
#endif
                                                                                           >
{
    @protected
    NSMutableURLRequest* _request;
    TDRemoteRequestCompletionBlock _onCompletion;
    NSURLConnection* _connection;
}

- (id) initWithMethod: (NSString*)method URL: (NSURL*)url body: (id)body
         onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;

// protected:
- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body;
- (void) clearConnection;
- (void) cancelWithStatus: (int)status;
- (void) respondWithResult: (id)result error: (NSError*)error;

@end


@interface TDRemoteJSONRequest : TDRemoteRequest
{
    @private
    NSMutableData* _jsonBuffer;
}
@end
