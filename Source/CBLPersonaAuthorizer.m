//
//  CBLPersonaAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/9/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLPersonaAuthorizer.h"
#import "CBLBase64.h"
#import "MYURLUtils.h"


static NSMutableDictionary* sAssertions;


@implementation CBLPersonaAuthorizer


static NSDictionary* decodeComponent(NSArray* components, NSUInteger index) {
    NSData* bodyData = [CBLBase64 decodeURLSafe: components[index]];
    if (!bodyData)
        return nil;
    return $castIf(NSDictionary, [CBLJSON JSONObjectWithData: bodyData options: 0 error: NULL]);
}


bool CBLParsePersonaAssertion(NSString* assertion,
                              NSString** outEmail, NSString** outOrigin, NSDate** outExp)
{
    // https://github.com/mozilla/id-specs/blob/prod/browserid/index.md
    // http://self-issued.info/docs/draft-jones-json-web-token-04.html
    NSArray* components = [assertion componentsSeparatedByString: @"."];
    if (components.count < 4)
        return false;
    NSDictionary* body = decodeComponent(components, 1);
    NSDictionary* principal = $castIf(NSDictionary, body[@"principal"]);
    *outEmail = $castIf(NSString, principal[@"email"]);

    body = decodeComponent(components, 3);
    *outOrigin = $castIf(NSString, body[@"aud"]);
    NSNumber* exp = $castIf(NSNumber, body[@"exp"]);
    *outExp = exp ? [NSDate dateWithTimeIntervalSince1970: exp.doubleValue / 1000.0] : nil;
    return *outEmail != nil && *outOrigin != nil && *outExp != nil;
}


+ (NSString*) registerAssertion: (NSString*)assertion {
    NSString* email, *origin;
    NSDate* exp;
    if (!CBLParsePersonaAssertion(assertion, &email, &origin, &exp))
        return nil;

    // Normalize the origin URL string:
    NSURL* originURL = [NSURL URLWithString:origin];
    if (!originURL)
        return nil;
    origin = originURL.my_baseURL.absoluteString;

    id key = @[email, origin];
    @synchronized(self) {
        if (!sAssertions)
            sAssertions = [NSMutableDictionary dictionary];
        sAssertions[key] = assertion;
    }
    return email;
}


+ (NSString*) assertionForEmailAddress: (NSString*)email site: (NSURL*)site
{
    id key = @[email, site.my_baseURL.absoluteString];
    @synchronized(self) {
        return sAssertions[key];
    }
}


@synthesize emailAddress=_emailAddress;


- (instancetype) initWithEmailAddress: (NSString*)emailAddress {
    self = [super init];
    if (self) {
        if (!emailAddress)
            return nil;
        _emailAddress = [emailAddress copy];
    }
    return self;
}


- (NSString*) assertion {
    NSURL* site = self.remoteURL;
    NSString* assertion = [[self class] assertionForEmailAddress: _emailAddress site: site];
    if (!assertion) {
        Warn(@"CBLPersonaAuthorizer<%@>: no assertion found for <%@>", _emailAddress, site);
        return nil;
    }
    NSString* email, *origin;
    NSDate* exp;
    if (!CBLParsePersonaAssertion(assertion, &email, &origin, &exp) || exp.timeIntervalSinceNow < 0) {
        Warn(@"CBLPersonaAuthorizer<%@>: assertion invalid or expired: %@", _emailAddress, assertion);
        return nil;
    }
    return assertion;
}


- (NSArray*) loginRequest {
    NSString* assertion = [self assertion];
    if (!assertion)
        return nil;
    return @[@"POST", @"_persona", assertion ];
}


@end
