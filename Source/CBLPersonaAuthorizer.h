//
//  CBLPersonaAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/9/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLAuthorizer.h"

/** Authorizer for the Persona decentralized-identity system. See http://persona.org */
@interface CBLPersonaAuthorizer: NSObject <CBLAuthorizer>

+ (NSString*) registerAssertion: (NSString*)assertion;

- (instancetype) initWithEmailAddress: (NSString*)emailAddress;

@property (readonly) NSString* emailAddress;

- (NSString*) assertionForSite: (NSURL*)site;

@end
