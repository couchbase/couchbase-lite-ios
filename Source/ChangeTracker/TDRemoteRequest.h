//
//  TDRemoteRequest.h
//  TouchDB
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef void (^TDRemoteRequestCompletionBlock)(id, NSError*);


@interface TDRemoteRequest : NSObject <NSURLConnectionDelegate>
{
    @private
    NSMutableURLRequest* _request;
    TDRemoteRequestCompletionBlock _onCompletion;
    NSURLConnection* _connection;
    NSMutableData* _inputBuffer;
}

- (id) initWithMethod: (NSString*)method URL: (NSURL*)url body: (id)body
         onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;

@end
