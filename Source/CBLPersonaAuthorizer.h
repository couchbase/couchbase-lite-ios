//
//  CBLPersonaAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/9/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLAuthorizer.h"

/** Authorizer for the Persona decentralized-identity system. See http://persona.org */
@interface CBLPersonaAuthorizer: CBLAuthorizer <CBLSessionCookieAuthorizer>

+ (NSString*) registerAssertion: (NSString*)assertion;

- (instancetype) initWithEmailAddress: (NSString*)emailAddress;

@property (readonly) NSString* emailAddress;

- (NSString*) assertion;

+ (NSString*) assertionForEmailAddress: (NSString*)email site: (NSURL*)site;

@end


// for testing
bool CBLParsePersonaAssertion(NSString* assertion,
                              NSString** outEmail, NSString** outOrigin, NSDate** outExp);
