//
//  ToyProtocol.h
//  ToyCouch
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ToyServer, ToyRouter;

@interface ToyProtocol : NSURLProtocol
{
    @private
    ToyRouter* _router;
}

+ (void) setServer: (ToyServer*)server;
+ (ToyServer*) server;

@end
