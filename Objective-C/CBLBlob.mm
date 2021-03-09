//
//  CBLBlob.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLBlob.h"
#import "CBLBlob+Swift.h"
#import "CBLBlobStream.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"
#import "c4BlobStore.h"
#import "CBLData.h"
#import "CBLErrorMessage.h"
#import "CBLJSON.h"

using namespace cbl;

extern "C" {
#import "MYErrorUtils.h"
}

// Max size of data that will be cached in memory with the CBLBlob
static const size_t kMaxCachedContentLength = 8*1024;

// Stack buffer size when reading NSInputStream
static const size_t kReadBufferSize = 8*1024;

NSString* const kCBLBlobType = @kC4ObjectType_Blob;
NSString* const kCBLTypeProperty = @kC4ObjectTypeProperty;
NSString* const kCBLBlobDigestProperty = @kC4BlobDigestProperty;
NSString* const kCBLBlobLengthProperty = @"length";
NSString* const kCBLBlobContentTypeProperty = @"content_type";

// internal
static NSString* const kCBLBlobDataProperty = @kC4BlobDataProperty;

@implementation CBLBlob
{
    CBLDatabase* _db;                       // nil if blob is new and unsaved
    NSData* _content;                       // If new from data, or already loaded from db
    NSInputStream* _initialContentStream;   // If new from stream.

    // A newly created unsaved blob will have either _content or _initialContentStream.
    // A new blob saved to the database will have _db and _digest.
    // A blob loaded from the database will have _db and _properties, and _digest unless invalid
}

@synthesize contentType=_contentType, length=_length, digest=_digest;
@synthesize swiftObject=_swiftObject;

- (instancetype) initWithContentType: (NSString*)contentType
                                data: (NSData*)data
{
    CBLAssertNotNil(contentType);
    CBLAssertNotNil(data);
    
    self = [super init];
    if(self) {
        _contentType = [contentType copy];
        _content = [data copy];
        _length = [data length];
    }
    
    return self;
}

- (instancetype) initWithContentType: (NSString*)contentType
                       contentStream: (NSInputStream*)stream
{
    CBLAssertNotNil(contentType);
    CBLAssertNotNil(stream);
    
    self = [super init];
    if(self) {
        _contentType = [contentType copy];
        _initialContentStream = stream;
    }
    
    return self;
}

- (instancetype) initWithContentType: (NSString*)contentType
                             fileURL: (NSURL*)url
                               error: (NSError**)outError
{
    CBLAssertNotNil(contentType);
    CBLAssertNotNil(url);
    Assert(url.isFileURL, kCBLErrorMessageNotFileBasedURL);
    
    NSInputStream* stream = [[NSInputStream alloc] initWithURL: url];
    if (!stream) {
        MYReturnError(outError, NSURLErrorFileDoesNotExist, NSURLErrorDomain,
                      @"File doesn't exist on %@", url.absoluteURL);
        return nil;
    }
    return [self initWithContentType: contentType
                       contentStream: stream];
}

// Initializer for an existing blob being read from a document
- (instancetype) initWithDatabase: (CBLDatabase*)db
                       properties: (NSDictionary *)properties
{
    Assert(db);
    Assert(properties);
    self = [super init];
    if(self) {
        _db = db;

        _length = asNumber(properties[kCBLBlobLengthProperty]).unsignedLongLongValue;
        _digest = asString(properties[kCBLBlobDigestProperty]);
        _contentType = asString(properties[kCBLBlobContentTypeProperty]);
        _content = asData(properties[kCBLBlobDataProperty]);
        if (!_digest && !_content)
            C4Warn("Blob read from database has neither digest nor data.");
    }
    return self;
}

- (void) dealloc {
    if (_initialContentStream)
        [_initialContentStream close];
    _initialContentStream = nil;
}

- (NSDictionary*) properties {
    @synchronized (self) {
        return $dict({kCBLTypeProperty, kCBLBlobType},
                     {kCBLBlobDigestProperty, _digest},
                     {kCBLBlobLengthProperty, (_length ? @(_length) : nil)},
                     {kCBLBlobContentTypeProperty, _contentType});
    }
}

- (NSDictionary*) jsonRepresentation {
    NSMutableDictionary* json = [self.properties mutableCopy];
    if (!json[kCBLBlobDigestProperty]) {
        json[kCBLBlobDataProperty] = self.content;
    }
    return json;
}

- (NSString*) toJSON {
    @synchronized (self) {
        if (!_digest)
            [NSException raise: NSInternalInconsistencyException
                        format: @"toJSON() is not allowed as Blob has not been saved in the database"];
    }
    
    NSError* error;
    NSString* s = [CBLJSON stringWithJSONObject: self.properties
                                        options: 0 error: &error];
    if (!s)
        CBLWarnError(Database, @"toJSON: Failed to serialize the json %@", error);
    
    return s;
}

- (BOOL) getBlobStore: (C4BlobStore**)outBlobStore andKey: (C4BlobKey*)outBlobKey {
    *outBlobStore = [_db getBlobStore: nullptr];
    return *outBlobStore && _digest && c4blob_keyFromString(CBLStringBytes(_digest), outBlobKey);
}

- (NSData*) content {
    @synchronized (self) {
        if(_content) {
            // Data is in memory:
            return _content;
        } else if (_db) {
            // Read blob from the BlobStore:
            C4BlobStore* blobStore;
            C4BlobKey key;
            if (![self getBlobStore: &blobStore andKey: &key])
                return nil;
            //TODO: If data is large, can get the file path & memory-map it
            FLSliceResult res = c4blob_getContents(blobStore, key, nullptr);
            NSData* content = sliceResult2data(res);
            FLSliceResult_Release(res);
            if (content && content.length <= kMaxCachedContentLength) {
                _content = content;
                _length = _content.length;
            }
            return content;
        } else {
            // No recourse but to read the initial stream into memory:
            if (!_initialContentStream) {
                [NSException raise: NSInternalInconsistencyException
                            format: @"%@", kCBLErrorMessageBlobContainsNoData];
            }
            
            NSMutableData *result = [NSMutableData new];
            uint8_t buffer[kReadBufferSize];
            NSInteger bytesRead;
            [_initialContentStream open];
            while((bytesRead = [_initialContentStream read:buffer maxLength:kReadBufferSize]) > 0) {
                [result appendBytes:buffer length:bytesRead];
            }
            [_initialContentStream close];
            if (bytesRead < 0)
                return nil;
            
            _initialContentStream = nil;
            _content = result;
            _length = _content.length;
            
            return _content;
        }
    }
}

- (NSInputStream*) contentStream {
    @synchronized (self) {
        if (_db) {
            C4BlobStore* blobStore;
            C4BlobKey key;
            if (![self getBlobStore: &blobStore andKey: &key])
                return nil;
            return [[CBLBlobStream alloc] initWithStore: blobStore key: key];
        } else {
            return _content ? [[NSInputStream alloc] initWithData: _content] : nil;
        }
    }
}

#pragma mark - Equality

- (BOOL) isEqual: (id)object {
    if (self == object)
        return YES;
    
    CBLBlob* other = $castIf(CBLBlob, object);
    if (other) {
        if (self.digest && other.digest)
            return [self.digest isEqualToString: other.digest];
        else
            return [self.content isEqual: other.content];
    }
    return NO;
}

- (NSUInteger) hash {
    return self.content.hash;
}

#pragma mark - Description

- (NSString*) description {
    @synchronized (self) {
        return [NSString stringWithFormat: @"%@[%@; %llu KB]",
                self.class, _contentType, (_length + 512)/1024];
    }
}

#pragma mark - Internal

- (BOOL) installInDatabase: (CBLDatabase*)db error:(NSError**)outError {
    Assert(db);
    if (_db) {
        if (_db != db) {
            [NSException raise: NSInternalInconsistencyException
                        format: @"%@", kCBLErrorMessageBlobDifferentDatabase];
        }
        return YES;
    }

    C4BlobStore *store = [db getBlobStore: outError];
    if (!store)
        return NO;

    C4Error err;
    C4BlobKey key;
    bool success = true;
    @synchronized (self) {
        if (_content) {
            success = c4blob_create(store, data2slice(_content), nullptr, &key, &err);
        } else {
            Assert(_initialContentStream, kCBLErrorMessageBlobContentNull);
            C4WriteStream* blobOut = c4blob_openWriteStream(store, &err);
            if(!blobOut)
                return convertError(err, outError);

            uint8_t buffer[kReadBufferSize];
            NSInteger bytesRead = 0;
            _length = 0;
            NSInputStream *contentStream = _initialContentStream;
            [contentStream open];
            success = true;
            while(success && (bytesRead = [contentStream read:buffer maxLength: kReadBufferSize]) > 0) {
                _length += bytesRead;
                success = c4stream_write(blobOut, buffer, bytesRead, &err);
            }
            if (bytesRead < 0) {
                // NSStream error. Set outError, but don't return until closing things down...
                success = false;
                if (outError)
                    *outError = contentStream.streamError;
            }

            [contentStream close];
            if (success) {
                key = c4stream_computeBlobKey(blobOut);
                success = c4stream_install(blobOut, nullptr, &err);
            }
            c4stream_closeWriter(blobOut);
            if (bytesRead < 0)
                return NO;  // NSStream error
        }
        
        if (!success)
            return convertError(err, outError);

        _digest = sliceResult2string(c4blob_keyToString(key));
        _db = db;
    }

    return YES;
}

#pragma mark FLEECE ENCODABLE

- (id) cbl_toCBLObject {
    return self;
}

- (void) fl_encodeToFLEncoder: (FLEncoder)encoder {
    // Note: If CBLDictionary can be encoded independently of CBLDocument,
    // so there could be no extra info:
    id extra = (__bridge id) FLEncoder_GetExtraInfo(encoder);
    CBLMutableDocument* document = $castIf(CBLMutableDocument, extra);
    if (document) {
        CBLDatabase* database = document.database;
        NSError *error;
        // Note: Installing blob in the database also updates the digest property.
        if (![self installInDatabase: database error: &error]) {
            [document setEncodingError: error];
            return;
        }
    }
    
    NSDictionary* dict = self.jsonRepresentation;
    FLEncoder_BeginDict(encoder, [dict count]);
    for (NSString *key in dict) {
        CBLStringBytes bKey(key);
        FLEncoder_WriteKey(encoder, bKey);
        id value = dict[key];
        FLEncoder_WriteNSObject(encoder, value);
    }
    FLEncoder_EndDict(encoder);
}

@end
