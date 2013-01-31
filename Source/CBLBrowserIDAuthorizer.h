//
//  CBLBrowserIDAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/9/13.
//
//

#import "CBLAuthorizer.h"

@interface CBLBrowserIDAuthorizer: NSObject <CBLAuthorizer>

+ (NSURL*) originForSite: (NSURL*)url;

+ (NSString*) registerAssertion: (NSString*)assertion;

- (id) initWithEmailAddress: (NSString*)emailAddress;

@property (readonly) NSString* emailAddress;

- (NSString*) assertionForSite: (NSURL*)site;

@end
