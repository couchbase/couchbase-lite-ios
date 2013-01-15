//
//  TDBrowserIDAuthorizer.h
//  TouchDB
//
//  Created by Jens Alfke on 1/9/13.
//
//

#import "TDAuthorizer.h"

@interface TDBrowserIDAuthorizer: NSObject <TDAuthorizer>

+ (NSURL*) originForSite: (NSURL*)url;

+ (void) registerAssertion: (NSString*)assertion
           forEmailAddress: (NSString*)email
                    toSite: (NSURL*)site;

- (id) initWithEmailAddress: (NSString*)emailAddress;

@property (readonly) NSString* emailAddress;

@end
