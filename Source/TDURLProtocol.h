//
//  TDURLProtocol.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDServer, TDRouter;

@interface TDURLProtocol : NSURLProtocol
{
    @private
    TDRouter* _router;
}

/** The root URL served by this protocol, "touchdb:///". */
+ (NSURL*) rootURL;

+ (void) setServer: (TDServer*)server;
+ (TDServer*) server;

@end
