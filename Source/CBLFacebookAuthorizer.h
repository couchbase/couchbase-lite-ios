//
//  CBLFacebookAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/7/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLAuthorizer.h"


/** Authorizer for Facebook-based logins. Connects to /_facebook endpoint on server. */
@interface CBLFacebookAuthorizer : CBLAuthorizer <CBLSessionCookieAuthorizer>

- (id) initWithEmailAddress: (NSString*)email;

/** Once the application code has received an access token from Facebook for a specific user
    and site, it calls this method to register it. The authorizer will then look up this token
    during replicator login and POST it to /_facebook on the server to create a login session. */
+ (bool) registerToken: (NSString*)token
       forEmailAddress: (NSString*)email
               forSite: (NSURL*)site;

- (NSString*) token;

@end
