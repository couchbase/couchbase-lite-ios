//
//  TDConnectionChangeTracker.h
//  TouchDB
//
//  Created by Jens Alfke on 12/1/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDChangeTracker.h"


/** TDChangeTracker that uses a regular NSURLConnection.
    This unfortunately doesn't work with regular CouchDB in continuous mode, apparently due to some bug in CFNetwork. */
@interface TDConnectionChangeTracker : TDChangeTracker
{
    @private
    NSURLConnection* _connection;
    NSMutableData* _inputBuffer;
    CFAbsoluteTime _startTime;
    bool _challenged;
}

@end
