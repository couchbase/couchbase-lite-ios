//
//  TDMultiStreamWriter.h
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
    NSUInteger _nextInputIndex;
    NSInputStream* _currentInput;
    uint8_t* _buffer;
    NSUInteger _bufferSize, _bufferLength;
    NSOutputStream* _output;
    NSInputStream* _input;
    NSError* _error;
    @protected
    SInt64 _length;
    SInt64 _totalBytesWritten;
}

- (void) addStream: (NSInputStream*)stream length: (UInt64)length;
- (void) addStream: (NSInputStream*)stream;
- (void) addData: (NSData*)data;
- (BOOL) addFileURL: (NSURL*)fileURL;
- (BOOL) addFile: (NSString*)path;

/** Total length of the stream.
    This is just computed by adding the values passed to -addStream:length:, and the lengths of the NSData objects and files added.
    If -addStream: has been called (the version without length:) the length is unknown and will be returned as -1.
    (Many clients won't care about the length, but TDMultipartUploader does.) */
@property (readonly) SInt64 length;

/** Returns an input stream; reading from this will return the contents of all added streams in sequence.
    This stream can be set as the HTTPBodyStream of an NSURLRequest.
    It is the caller's responsibility to close the returned stream. */
- (NSInputStream*) openForInputStream;

/** Associates an output stream; the data from all of the added streams will be written to the output, asynchronously. */
- (void) openForOutputTo: (NSOutputStream*)output;

- (void) close;

@property (readonly) BOOL isOpen;

@property (readonly, strong) NSError* error;

/** Convenience method that opens an output stream, collects all the data, and returns it. */
- (NSData*) allOutput;

// protected:
- (void) addInput: (id)input length: (UInt64)length;
- (void) opened;
@end
