//
//  ToyProtocol.h
//  ToyCouch
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ToyServer, ToyResponse;

@interface ToyProtocol : NSURLProtocol

+ (void) setServer: (ToyServer*)server;

@end
