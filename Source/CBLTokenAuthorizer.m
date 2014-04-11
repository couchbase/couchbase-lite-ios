//
//  CBLTokenAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/11/14.
//  Copyright (c) 2014 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#import "CBLTokenAuthorizer.h"

@implementation CBLTokenAuthorizer
{
    NSString* _loginPath;
    NSDictionary* _loginParams;
}

- (instancetype) initWithLoginPath: (NSString*)loginPath
                    postParameters: (NSDictionary*)params
{
    self = [super init];
    if (self) {
        _loginPath = [loginPath copy];
        _loginParams = [params copy];
    }
    return self;
}


- (NSString*) loginPathForSite: (NSURL*)site {
    return [site.path stringByAppendingPathComponent: _loginPath];
}


- (NSDictionary*) loginParametersForSite: (NSURL*)site {
    return _loginParams;
}


- (NSString*) authorizeURLRequest: (NSMutableURLRequest*)request
                         forRealm: (NSString*)realm
{
    return nil; // no-op
}


- (NSString*) authorizeHTTPMessage: (CFHTTPMessageRef)message
                          forRealm: (NSString*)realm
{
    return nil; // no-op
}



@end
