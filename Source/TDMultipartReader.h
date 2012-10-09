//
//  TDMultipartReader.h
//  TouchDB
//
//  Created by Jens Alfke on 1/30/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@protocol TDMultipartReaderDelegate;


/** Streaming MIME multipart reader. */
@interface TDMultipartReader : NSObject
{
    @private
    id<TDMultipartReaderDelegate> _delegate;
    NSData* _boundary;
    NSMutableData* _buffer;
    NSMutableDictionary* _headers;
    int _state;
    NSString* _error;
}

/** Initializes the reader.
    Returns nil if the content type isn't a valid multipart type, or doesn't contain a "boundary" parameter.
    @param contentType the entire MIME Content-Type string, with parameters.
    @param delegate  The delegate object that will be called as parts are parsed. */
- (id) initWithContentType: (NSString*)contentType
                  delegate: (id<TDMultipartReaderDelegate>)delegate;

/** Call this when more data is available. */
- (void) appendData: (NSData*)data;

/** Has the reader successfully finished reading the entire multipart body? */
@property (readonly) BOOL finished;

/** Was there a fatal parse error? */
@property (readonly) NSString* error;

/** The MIME headers of the part currently being parsed.
    You can call this from your -appendToPart and/or -finishedPart overrides. */
@property (readonly) NSDictionary* headers;

@end



@protocol TDMultipartReaderDelegate <NSObject>

/** This method is called when a part's headers have been parsed, before its data is parsed. */
- (void) startedPart: (NSDictionary*)headers;

/** This method is called to append data to a part's body. */
- (void) appendToPart: (NSData*)data;

/** This method is called when a part is complete. */
- (void) finishedPart;

@end