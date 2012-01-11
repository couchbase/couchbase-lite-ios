//
//  TDMultipartWriter.h
//  TouchDB
//
//  Created by Jens Alfke on 1/10/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Generates a MIME multipart body. */
@interface TDMultipartWriter : NSObject
{
    NSString* _contentType;
    NSString* _boundary;
    NSMutableData* _body;
}

- (id) initWithContentType: (NSString*)type;

/** Adds another part. */
- (void) addPart: (NSData*)part withHeaders: (NSDictionary*)headers;

/** This will include the ";boundary=" parameter as well as the base type. */
@property (readonly) NSString* contentType;

/** The entire body so far. */
@property (readonly) NSData* body;

@end
