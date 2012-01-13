//
//  TDHTTPConnection.h
//  TouchDB
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "HTTPConnection.h"
@class TDListener;


@interface TDHTTPConnection : HTTPConnection

@property (readonly) TDListener* listener;

@end
