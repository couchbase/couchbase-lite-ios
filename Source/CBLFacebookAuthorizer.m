//
//  CBLFacebookAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/7/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLFacebookAuthorizer.h"
#import "MYURLUtils.h"


#define kLoginParamAccessToken @"access_token"


static NSMutableDictionary* sRegisteredTokens;


@implementation CBLFacebookAuthorizer
{
    NSString* _email;
}


- (id)initWithEmailAddress:(NSString *)email {
    self = [super init];
    if (self) {
        if (!email)
            return nil;
        _email = email;
    }
    return self;
}


+ (bool) registerToken: (NSString*)token
       forEmailAddress: (NSString*)email
               forSite: (NSURL*)site
{
    id key = @[email, site.my_baseURL.absoluteString];
    @synchronized(self) {
        if (!sRegisteredTokens)
            sRegisteredTokens = [NSMutableDictionary dictionary];
        [sRegisteredTokens setValue: token forKey: key];
    }
    return true;
}


- (NSString*) token {
    id key = @[_email, self.remoteURL.my_baseURL.absoluteString];
    @synchronized([self class]) {
        return sRegisteredTokens[key];
    }
}


- (NSArray*) loginRequest {
    NSString* token = [self token];
    if (!token)
        return nil;
    return @[@"POST", @"_facebook", @{kLoginParamAccessToken: token} ];
}


@end
