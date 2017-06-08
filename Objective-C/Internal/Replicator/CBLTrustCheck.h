//
//  CBLTrustUtils.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Security/SecTrust.h>

@interface CBLTrustCheck : NSObject

+ (void) setAnchorCerts: (NSArray*)certs
              onlyThese: (BOOL)onlyThese;

- (instancetype) initWithChallenge: (NSURLAuthenticationChallenge*)challenge;

- (instancetype) initWithTrust: (SecTrustRef)trust
                          host: (NSString*)host
                          port: (uint16_t)port;

@property (copy, atomic) NSData* pinnedCertData;

- (NSURLCredential*) checkTrust: (NSError**)outError;

@end
