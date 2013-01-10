//
//  TDBrowserIDAuthorizer.h
//  TouchDB
//
//  Created by Jens Alfke on 1/9/13.
//
//

#import "TDAuthorizer.h"

@interface TDBrowserIDAuthorizer: NSObject <TDAuthorizer>

- (id) initWithAssertion: (NSString*)assertion;

@property (readonly) NSString* assertion;

@end
