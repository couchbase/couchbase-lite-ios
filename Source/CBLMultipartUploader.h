//
//  CBLMultipartUploader.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/5/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteRequest.h"
#import "CBLMultipartWriter.h"


@interface CBLMultipartUploader : CBLRemoteRequest
{
    @private
    CBLMultipartWriter* _multipartWriter;
}

- (instancetype) initWithURL: (NSURL *)url
                    streamer: (CBLMultipartWriter*)streamer
              requestHeaders: (NSDictionary *) requestHeaders
        allowsCellularAccess: (BOOL)allowsCellularAccess
                onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion;

@end
