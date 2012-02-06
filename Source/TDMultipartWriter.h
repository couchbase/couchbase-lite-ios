//
//  TDMultipartWriter.h
//  TouchDB
//
//  Created by Jens Alfke on 2/2/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDMultiStreamWriter.h"


/** A streaming MIME multipart body generator, suitable for use with an NSURLRequest.
    Reads from a sequence of input streams (or data blobs) and inserts boundary strings between them. Can keep track of the total MIME body length so you can set it as the request's Content-Length, for servers that have trouble with chunked encodings. */
@interface TDMultipartWriter : TDMultiStreamWriter
{
    @private
    NSString* _boundary;
    NSString* _contentType;
    NSData* _separatorData;
    NSDictionary* _nextPartsHeaders;
    UInt64 _length;
}

/** Initializes an instance.
    @param type  The base content type, e.g. "application/json".
    @param boundary  The MIME part boundary to use, or nil to automatically generate one (a long random string). If you specify a boundary, you have to ensure that it appears nowhere in any of the input data! */
- (id) initWithContentType: (NSString*)type boundary: (NSString*)boundary;

/** The full MIME Content-Type header value, including the boundary parameter. */
@property (readonly) NSString* contentType;

/** The boundary string. */
@property (readonly) NSString* boundary;

/** Call this before adding a new stream/data/file to specify the MIME headers that should go with it. */
- (void) setNextPartsHeaders: (NSDictionary*)headers;

/** Add a stream and tell the streamer its length so it can adjust its .length property.
    You can also call the inherited -addData: and -addFile: methods; those will get the length of the data/file for you. */
- (void) addStream: (NSInputStream*)partStream length:(UInt64)length;

/** Total length of the stream.
    This is just computed by adding the values passed to -addStream:length:, and the lengths of the NSData objects and files added, plus the MIME boundary strings.
    Many clients won't care about the length, but TDMultipartUploader does. */
@property (readonly, nonatomic) UInt64 length;

/** Attaches the writer to the URL request.
    This calls -openForInputStream and sets the resulting input stream as the HTTPBodyStream of the request. It also sets the Content-Type header of the request. */
- (void) openForURLRequest: (NSMutableURLRequest*)request;

@end
