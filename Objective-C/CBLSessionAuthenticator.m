//
//  CBLSessionAuthenticator.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLSessionAuthenticator.h"
#import "CBLAuthenticator+Internal.h"
#import "CBLJSON.h"

#define kDefaultCookieName @"SyncGatewaySession"

@implementation CBLSessionAuthenticator

@synthesize sessionID=_sessionID, cookieName=_cookieName;


- (instancetype) initWithSessionID: (NSString*)sessionID {
    return [self initWithSessionID: sessionID cookieName: nil];
}


- (instancetype) initWithSessionID: (NSString*)sessionID
                        cookieName: (nullable NSString*)cookieName
{
    CBLAssertNotNil(sessionID);
    
    self = [super initWithNone];
    if (self) {
        _sessionID = sessionID;
        _cookieName = cookieName ? cookieName : kDefaultCookieName;
    }
    return self;
}


- (void) authenticate: (NSMutableDictionary*)options {
    NSString* current = options[@kC4ReplicatorOptionCookies];
    NSMutableString* cookieStr = current ?
        [NSMutableString stringWithString: current] : [NSMutableString new];
    
    if (cookieStr.length > 0)
        [cookieStr appendString: @"; "];
    
    // TODO: How about expires?
    [cookieStr appendFormat: @"%@=%@", _cookieName, _sessionID];
    
    options[@kC4ReplicatorOptionCookies] = cookieStr;
}


#pragma mark - Private


- (nullable NSDate*) convertExpires: (nullable id)expires {
    if (!expires || [expires isKindOfClass: [NSDate class]])
        return expires;
    
    NSParameterAssert([expires isKindOfClass: [NSString class]]);
    return [CBLJSON dateWithJSONObject: expires];
}


@end
