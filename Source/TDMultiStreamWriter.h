//
//  TDMultiInputStream.h
//  TouchDB
//
//  Created by Jens Alfke on 2/3/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/** A stream aggregator that reads from a concatenated sequence of other inputs.
    Use this to combine multiple input streams (and data blobs) together into one.
    This is useful when uploading multipart MIME bodies. */
@interface TDMultiStreamWriter : NSObject
{
    @private
    NSMutableArray* _inputs;
    NSInputStream* _currentInput;
    uint8_t* _buffer;
    NSUInteger _bufferSize, _bufferLength;
    NSOutputStream* _output;
    NSInputStream* _input;
}

- (void) addStream: (NSInputStream*)stream;
- (void) addData: (NSData*)data;
- (BOOL) addFile: (NSString*)path;

/** Returns an input stream; reading from this will return the contents of all added streams in sequence.
    This stream can be set as the HTTPBodyStream of an NSURLRequest. */
- (NSInputStream*) openForInputStream;

/** Associates an output stream; the data from all of the added streams will be written to the output, asynchronously. */
- (void) openForOutputTo: (NSOutputStream*)output;

- (void) close;

@property (readonly) BOOL isOpen;

/** Convenience method that opens an output stream, collects all the data, and returns it. */
- (NSData*) allOutput;

// protected:
- (void) opened;
@end
