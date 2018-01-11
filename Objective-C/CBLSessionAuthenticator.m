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

#define kDefaultCookieName @"SyncGatewaySession"

@implementation CBLSessionAuthenticator

@synthesize sessionID=_sessionID, cookieName=_cookieName;


- (instancetype) initWithSessionID: (NSString*)sessionID {
    return [self initWithSessionID: sessionID cookieName: nil];
}


- (instancetype) initWithSessionID: (NSString*)sessionID
                        cookieName: (nullable NSString*)cookieName
{
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
