//
//  CBL_Attachment.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/3/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Attachment.h"
#import "CBLBase64.h"
#import "CBLDatabase+Internal.h"
#import "CBL_BlobStore.h"
#import "CBLGZip.h"


static NSString* blobKeyToDigest(CBLBlobKey key) {
    return [@"sha1-" stringByAppendingString: [CBLBase64 encode: &key length: sizeof(key)]];
}

@implementation CBL_Attachment
{
    CBLBlobKey _blobKey;
    NSString* _digest;
    NSData* _data;
}


@synthesize name=_name, contentType=_contentType, database=_database;


+ (bool) digest: (NSString*)digest toBlobKey: (CBLBlobKey*)outKey {
    if (![digest hasPrefix: @"sha1-"])
        return false;
    NSData* keyData = [CBLBase64 decode: [digest substringFromIndex: 5]];
    if (!keyData || keyData.length != sizeof(CBLBlobKey))
        return nil;
    *outKey = *(CBLBlobKey*)keyData.bytes;
    return true;
}


- (instancetype) initWithName: (NSString*)name contentType: (NSString*)contentType {
    Assert(name);
    self = [super init];
    if (self) {
        _name = [name copy];
        _contentType = [contentType copy];
    }
    return self;
}


- (instancetype) initWithName: (NSString*)name
                         info: (NSDictionary*)attachInfo
                       status: (CBLStatus*)outStatus
{
    self = [self initWithName: name contentType: $castIf(NSString, attachInfo[@"content_type"])];
    if (self) {
        NSNumber* explicitLength = $castIf(NSNumber, attachInfo[@"length"]);
        self->length = explicitLength.unsignedLongLongValue;
        explicitLength = $castIf(NSNumber, attachInfo[@"encoded_length"]);
        self->encodedLength = explicitLength.unsignedLongLongValue;

        _digest = $castIf(NSString, attachInfo[@"digest"]);
        if (_digest)
            [[self class] digest: _digest toBlobKey: &_blobKey]; // (but digest might not map to a blob key)

        NSString* encodingStr = $castIf(NSString, attachInfo[@"encoding"]);
        if (encodingStr) {
            if ($equal(encodingStr, @"gzip")) {
                self->encoding = kCBLAttachmentEncodingGZIP;
            } else {
                *outStatus = kCBLStatusBadEncoding;
                return nil;
            }
        }

        id data = attachInfo[@"data"];
        if (data) {
            // If there's inline attachment data, decode and store it:
            if ([data isKindOfClass: [NSString class]]) {
                @autoreleasepool {
                    _data = [CBLBase64 decode: data];
                }
            } else {
                _data = $castIf(NSData, data);
            }
            if (!_data) {
                *outStatus = kCBLStatusBadEncoding;
                return nil;
            }
            self.possiblyEncodedLength = _data.length;
        } else {
            // Get the revpos:
            id revPosObj = attachInfo[@"revpos"];
            if (revPosObj) {
                int revPos = [$castIf(NSNumber, revPosObj) intValue];
                if (revPos <= 0) {
                    *outStatus = kCBLStatusBadAttachment;
                    return nil;
                }
                self->revpos = (unsigned)revPos;
            }
            if ([attachInfo[@"stub"] isEqual: $true]) {
                // Stub with nothing else
                return self;
            } else if ([attachInfo[@"follows"] isEqual: $true]) {
                // Attachment with _follows must have a digest to match with the MIME body
                if (!_digest) {
                    *outStatus = kCBLStatusBadAttachment;
                    return nil;
                }
            } else {
                *outStatus = kCBLStatusBadAttachment;
                return nil;
            }
        }
    }
    return self;
}


- (void) setPossiblyEncodedLength: (UInt64)len {
    if (self->encoding)
        self->encodedLength = len;
    else
        self->length = len;
}


- (BOOL) hasBlobKey {
    size_t i;
    for (i=0; i<sizeof(CBLBlobKey); i++)
        if (_blobKey.bytes[i])
            return true;
    return false;
}


- (CBLBlobKey) blobKey {
    return _blobKey;
}

- (void) setBlobKey: (CBLBlobKey)blobKey {
    _blobKey = blobKey;
    _digest = nil;
}


- (NSString*) digest {
    if (_digest)
        return _digest;
    else if (self.hasBlobKey)
        return blobKeyToDigest(_blobKey);
    else
        return nil;
}


- (BOOL) isValid {
    if (encoding) {
        if (encodedLength == 0 && length > 0)
            return false;
    } else if (encodedLength > 0)
        return false;
    else if (revpos == 0)
        return false;
#if DEBUG
    else if (!self.hasBlobKey)
        return false;
#endif
    return true;
}


- (NSDictionary*) asStubDictionary {
    NSMutableDictionary* dict = $mdict({@"stub", $true},
                                       {@"digest", blobKeyToDigest(_blobKey)},
                                       {@"content_type", _contentType},
                                       {@"revpos", @(revpos)},
                                       {@"length", @(length)});
    if (encodedLength > 0)
        dict[@"encoded_length"] = @(encodedLength);
    switch (encoding) {
        case kCBLAttachmentEncodingGZIP:
            dict[@"encoding"] = @"gzip";
            break;
        case kCBLAttachmentEncodingNone:
            break;
    }
    return dict;
}


- (BOOL) hasContent {
    return [_database.attachmentStore hasBlobForKey: _blobKey];
}


- (NSData*) encodedContent {
    if (_data)
        return _data;
    else
        return [_database.attachmentStore blobForKey: _blobKey];
}


- (NSData*) content {
    NSData* data = self.encodedContent;
    if (data) {
        switch (encoding) {
            case kCBLAttachmentEncodingNone:
                break;
            case kCBLAttachmentEncodingGZIP:
                data = [CBLGZip dataByDecompressingData: data];
                if (!data)
                    Warn(@"Unable to decode attachment!");
        }
    }
    return data;
}


- (NSInputStream*) contentStream {
    if (encoding == kCBLAttachmentEncodingNone)
        return [_database.attachmentStore blobInputStreamForKey: _blobKey length: NULL];
    else {
        NSData* content = self.content;
        return content ? [NSInputStream inputStreamWithData: content] : nil;
    }
}


- (NSURL*) contentURL {
    NSString* path = [_database.attachmentStore blobPathForKey: _blobKey];
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: NULL])
        return nil;
    return [NSURL fileURLWithPath: path];
}


@end
