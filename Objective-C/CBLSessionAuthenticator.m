//
//  CBLSessionAuthenticator.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLSessionAuthenticator.h"
#import "CBLAuthenticator+Internal.h"
#import "CBLJSON.h"

@implementation CBLSessionAuthenticator

@synthesize sessionID=_sessionID, expires=_expires, cookieName=_cookieName;


- (instancetype) initWithSessionID: (NSString*)sessionID
                      expireString: (nullable id)expires
                        cookieName: (NSString*)cookieName
{
    return [self initWithSessionID: sessionID
                        expireDate: [self convertExpires: expires]
                        cookieName: cookieName];
}


- (instancetype) initWithSessionID: (NSString*)sessionID
                        expireDate: (nullable NSDate*)expires
                        cookieName: (NSString*)cookieName
{
    self = [super init];
    if (self) {
        _sessionID = sessionID;
        _expires = expires;
        _cookieName = cookieName;
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
