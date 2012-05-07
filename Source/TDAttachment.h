//
//  TDAttachment.h
//  TouchDB
//
//  Created by Jens Alfke on 4/3/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase+Attachments.h"
#import "TDBlobStore.h"


/** A simple container for attachment metadata. */
@interface TDAttachment : NSObject
{
    @private
    NSString* _name;
    NSString* _contentType;
    @public
    // Yes, these are public. They're simple scalar values so it's not really worth
    // creating accessor methods for them all.
    TDBlobKey blobKey;
    UInt64 length;
    UInt64 encodedLength;
    TDAttachmentEncoding encoding;
    unsigned revpos;
}

- (id) initWithName: (NSString*)name contentType: (NSString*)contentType;

@property (readonly, nonatomic) NSString* name;
@property (readonly, nonatomic) NSString* contentType;

@property (readonly) bool isValid;

@end
