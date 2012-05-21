//
//  TDOAuth1Authorizer.h
//  TouchDB
//
//  Created by Jens Alfke on 5/21/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDAuthorizer.h"
@class OAConsumer, OAToken;
@protocol OASignatureProviding;


/** Implementation of TAuthorizer for OAuth 1 requests. */
@interface TDOAuth1Authorizer : NSObject <TDAuthorizer>
{
    OAConsumer* _consumer;
    OAToken* _token;
    id<OASignatureProviding> _signatureProvider;
}

- (id) initWithConsumerKey: (NSString*)consumerKey
            consumerSecret: (NSString*)consumerSecret
                     token: (NSString*)token
               tokenSecret: (NSString*)tokenSecret
           signatureMethod: (NSString*)signatureMethod;

@end
