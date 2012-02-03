//
//  TDMultipartStreamer.h
//  TouchDB
//
//  Created by Jens Alfke on 2/2/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDMultiInputStream.h"


/** A streaming MIME multipart body generator, intended to be set as the HTTPBodyStream of an NSURLRequest..
    Reads from a sequence of input streams (or data blobs) and inserts boundary strings between them. Can keep track of the total MIME body length so you can set it as the request's Content-Length, for servers that have trouble with chunked encodings. */
@interface TDMultipartStreamer : TDMultiInputStream
{
    @private
    NSString* _boundary;
    NSData* _separatorData;
    NSDictionary* _nextPartsHeaders;
    UInt64 _length;
}

/** Initializes an instance.
    @param boundary  The MIME part boundary to use, or nil to automatically generate one (a long random string). If you specify a boundary, you have to ensure that it appears nowhere in any of the inputs. */
- (id) initWithBoundary: (NSString*)boundary;

/** The boundary string. You'll want to put this in the Content-Type header. */
@property (readonly) NSString* boundary;

/** Call this before adding a new stream/data/file to specify the MIME headers that should go with it. */
- (void) setNextPartsHeaders: (NSDictionary*)headers;

/** Add a stream and tell the streamer its length so it can adjust its .length property.
    You can also call the inherited -addData: and -addFile: methods; those will get the length of the data/file for you. */
- (void) addStream: (NSInputStream*)partStream length:(UInt64)length;

/** Total length of the stream so far.
    This is just computed by adding the values passed to -addStream:length:, and the lengths of the NSData objects and files added, plus the MIME boundary strings.
    Many clients won't care about the length, but TDMultipartUploader does. */
@property (readonly, nonatomic) UInt64 length;

@end
