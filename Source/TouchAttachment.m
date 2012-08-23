//
//  TouchAttachment.m
//  TouchDB
//
//  Created by Jens Alfke on 6/21/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchAttachment.h"
#import "TouchDBPrivate.h"

#import "TDDatabase+Attachments.h"
#import "TDBlobStore.h"
#import "TDInternal.h"


@implementation TouchAttachment


- (id) initWithRevision: (TouchRevision*)rev
                   name: (NSString*)name
               metadata: (NSDictionary*)metadata
{
    NSParameterAssert(rev);
    NSParameterAssert(name);
    NSParameterAssert(metadata);
    self = [super init];
    if (self) {
        _rev = [rev retain];
        _name = [name copy];
        _metadata = [metadata copy];
    }
    return self;
}


- (id) initWithContentType: (NSString*)contentType
                      body: (id)body
{
    NSParameterAssert(contentType);
    NSParameterAssert(body);
    Assert([body isKindOfClass: [NSData class]] ||
                 ([body isKindOfClass: [NSURL class]] && [body isFileURL]),
           @"Invalid attachment body: %@", body);
    self = [super init];
    if (self) {
        _metadata = [$dict({@"content_type", contentType},
                           {@"follows", $true}) retain];
        _body = [body retain];
    }
    return self;
}


- (void)dealloc {
    [_rev release];
    [_metadata release];
    [_body release];
    [super dealloc];
}


@synthesize revision=_rev, name=_name, metadata=_metadata;


- (TouchDocument*) document {
    return _rev.document;
}


- (NSString*) contentType {
    return $castIf(NSString, [_metadata objectForKey: @"content_type"]);
}


- (UInt64) length {
    NSNumber* lengthObj = $castIf(NSNumber, [_metadata objectForKey: @"length"]);
    return lengthObj ? [lengthObj longLongValue] : 0;
}


#pragma mark - BODY


- (NSData*) newBody {
    return _body ? self.body : nil;
}


- (NSData*) body {
    if (_body) {
        if ([_body isKindOfClass: [NSData class]])
            return _body;
        else if ([_body isKindOfClass: [NSURL class]] && [_body isFileURL]) {
            return [NSData dataWithContentsOfURL: _body
                                         options: NSDataReadingMappedIfSafe | NSDataReadingUncached
                                           error: nil];
        } else
            return nil;
    } else {
        TDStatus status;
        return [_rev.database.tddb getAttachmentForSequence: _rev.sequence
                                                      named: _name
                                                       type: NULL encoding: NULL
                                                     status: &status];
    }
}


- (TouchRevision*) updateBody: (NSData*)body
                  contentType: (NSString*)contentType
                        error: (NSError**)outError
{
    Assert(_rev);
    TDStatus status;
    TDRevision* newRev = [_rev.database.tddb updateAttachment: _name
                                                         body: body
                                                         type: contentType ?: self.contentType
                                                     encoding: kTDAttachmentEncodingNone
                                                      ofDocID: _rev.document.documentID
                                                        revID: _rev.revisionID
                                                       status: &status];
    if (!newRev) {
        if (outError) *outError = TDStatusToNSError(status, nil);
        return nil;
    }
    return [[[TouchRevision alloc] initWithDocument: self.document revision: newRev] autorelease];
}


// Goes through an _attachments dictionary and replaces any values that are TouchAttachment objects
// with proper JSON metadata dicts. It registers the attachment bodies with the blob store and sets
// the metadata 'digest' and 'follows' properties accordingly.
+ (NSDictionary*) installAttachmentBodies: (NSDictionary*)attachments
                             intoDatabase: (TouchDatabase*)database
{
    TDDatabase* tddb = database.tddb;
    return [attachments my_dictionaryByUpdatingValues: ^id(NSString* name, id value) {
        TouchAttachment* attachment = $castIf(TouchAttachment, value);
        if (attachment) {
            // Replace the attachment object with a metadata dictionary:
            NSMutableDictionary* metadata = [[attachment.metadata mutableCopy] autorelease];
            value = metadata;
            NSData* body = attachment.newBody;
            if (body) {
                // Copy attachment body into the database's blob store:
                // OPT: If _body is an NSURL, could just copy the file without reading into RAM
                TDBlobStoreWriter* writer = tddb.attachmentWriter;
                [writer appendData: body];
                [writer finish];
                [metadata setObject: $object(body.length) forKey: @"length"];
                [metadata setObject: writer.MD5DigestString forKey: @"digest"];
                [metadata setObject: $true forKey: @"follows"];
                [tddb rememberAttachmentWriter: writer];
            }
        }
        return value;
    }];
}


@end
