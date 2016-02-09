//
//  CBLMultipartUploader.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/5/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteRequest.h"
#import "CBLMultipartWriter.h"

/** The signature of the mulipart writer block called by the CBLMultipartUploader to 
    get a CBLMultipartWriter object. When the CBLMultipartUploader is doing retry, it
    will call the block to get a new writer object. It cannot reuse the old writer object
    as all of the streams have already been opened and cannot be reopened. */
typedef CBLMultipartWriter* (^CBLMultipartUploaderMultipartWriterBlock)(void);

@interface CBLMultipartUploader : CBLRemoteRequest
{
    @private
    CBLMultipartUploaderMultipartWriterBlock _writer;
    CBLMultipartWriter* _currentWriter;
}

- (instancetype) initWithURL: (NSURL *)url
             multipartWriter: (CBLMultipartUploaderMultipartWriterBlock)writer
                onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion;

@end
