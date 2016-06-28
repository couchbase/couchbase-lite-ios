//
//  CBLOpenIDConnectAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/19/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLAuthorizer.h"
#import "CBLAuthenticator+OpenID.h"


NS_ASSUME_NONNULL_BEGIN

@interface CBLOpenIDConnectAuthorizer : CBLAuthorizer <CBLLoginAuthorizer,
                                                       CBLCustomHeadersAuthorizer,
                                                       CBLSessionCookieAuthorizer>

- (instancetype) initWithCallback: (CBLOIDCLoginCallback)callback;

+ (BOOL) forgetIDTokensForServer: (NSURL*)serverURL
                           error: (NSError**)outError;

#if DEBUG
@property (copy, nullable) NSString* IDToken, *refreshToken;  // for testing only
#endif

@end

NS_ASSUME_NONNULL_END
