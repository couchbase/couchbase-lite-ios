//
//  TDSocketChangeTracker.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDChangeTracker.h"


/** TDChangeTracker implementation that uses a raw TCP socket to read the chunk-mode HTTP response. */
@interface TDSocketChangeTracker : TDChangeTracker
{
    @private
    NSInputStream* _trackingInput;
    
    NSMutableData* _inputBuffer;
    NSMutableData* _changeBuffer;
    CFHTTPMessageRef _unauthResponse;
    NSURLCredential* _credential;
    CFAbsoluteTime _startTime;
    bool _gotResponseHeaders;
    bool _parsing;
    bool _inputAvailable;
    bool _atEOF;
}
@end
