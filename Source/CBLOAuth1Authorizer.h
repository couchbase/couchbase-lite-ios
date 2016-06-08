//
//  CBLOAuth1Authorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLAuthorizer.h"
@class OAConsumer, OAToken;
@protocol OASignatureProviding;


/** Implementation of TAuthorizer for OAuth 1 requests. */
@interface CBLOAuth1Authorizer : CBLAuthorizer <CBLCustomHeadersAuthorizer>
{
    OAConsumer* _consumer;
    OAToken* _token;
    id<OASignatureProviding> _signatureProvider;
}

- (instancetype) initWithConsumerKey: (NSString*)consumerKey
                      consumerSecret: (NSString*)consumerSecret
                               token: (NSString*)token
                         tokenSecret: (NSString*)tokenSecret
                     signatureMethod: (NSString*)signatureMethod;

@end
