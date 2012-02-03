//
//  TDMultiInputStream.h
//  TouchDB
//
//  Created by Jens Alfke on 2/3/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/** An input stream that reads from a concatenated sequence of other inputs.
    Use this to combine multiple input streams (and data blobs) together into one.
    This is useful when uploading multipart MIME bodies. */
@interface TDMultiInputStream : NSInputStream <NSStreamDelegate>
{
    @private
    NSMutableArray* _inputs;
    NSInputStream* _currentInput;
    NSMutableArray* _runLoopsAndModes;
    id<NSStreamDelegate> _delegate;
    CFOptionFlags _cfClientFlags;
    CFReadStreamClientCallBack _cfClientCallback;
    CFStreamClientContext _cfClientContext;
}

@property (assign) id<NSStreamDelegate> delegate;

- (void) addStream: (NSInputStream*)stream;
- (void) addData: (NSData*)data;
- (BOOL) addFile: (NSString*)path;

@end
