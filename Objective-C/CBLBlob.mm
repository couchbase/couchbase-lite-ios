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
#import "CBLCollection+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"
#import "c4BlobStore.h"
#import "CBLData.h"
#import "CBLErrorMessage.h"
#import "CBLJSON.h"
#import "CBLFleece.hh"

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
        
        [self setProperties: properties];
    }
    return self;
}

// Initializer for an existing blob without a DB
- (instancetype) initWithProperties:(NSDictionary *)properties {
    Assert(properties);
    self = [super init];
    if(self) {
        [self setProperties: properties];
    }
    return self;
}

- (void) setProperties:(NSDictionary<NSString *,id>*)properties {
    _length = asNumber(properties[kCBLBlobLengthProperty]).unsignedLongLongValue;
    _digest = asString(properties[kCBLBlobDigestProperty]);
    _contentType = asString(properties[kCBLBlobContentTypeProperty]);
    _content = asData(properties[kCBLBlobDataProperty]);
    if (!_digest && !_content)
        C4Warn("Blob read from database has neither digest nor data.");
}

- (void) dealloc {
    if (_initialContentStream)
        [_initialContentStream close];
    _initialContentStream = nil;
}

- (NSDictionary*) properties {
    CBL_LOCK(self) {
        return $dict({kCBLBlobDigestProperty, _digest},
                     {kCBLBlobLengthProperty, (_length ? @(_length) : nil)},
                     {kCBLBlobContentTypeProperty, _contentType});
    }
}

- (NSDictionary*) blobProperties: (BOOL)mayIncludeContent {
    NSMutableDictionary* json = [self.properties mutableCopy];
    json[kCBLTypeProperty] = kCBLBlobType;
    if (mayIncludeContent && !json[kCBLBlobDigestProperty]) {
        json[kCBLBlobDataProperty] = self.content;
    }
    return json;
}

- (NSString*) toJSON {
    CBL_LOCK(self) {
        if (!_digest)
            [NSException raise: NSInternalInconsistencyException
                        format: @"toJSON() is not allowed as Blob has not been saved in the database"];
    }
    
    NSError* error;
    NSString* s = [CBLJSON stringWithJSONObject: [self blobProperties: NO]
                                        options: 0 error: &error];
    
    // it should always return valid json string
    assert(s);
    
    return s;
}

- (BOOL) getBlobStore: (C4BlobStore**)outBlobStore andKey: (C4BlobKey*)outBlobKey {
    *outBlobStore = [_db getBlobStore: nullptr];
    return *outBlobStore && _digest && c4blob_keyFromString(CBLStringBytes(_digest), outBlobKey);
}

- (NSData*) content {
    CBL_LOCK(self) {
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
        } else if (_initialContentStream) {
            // No recourse but to read the initial stream into memory:
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
        } else {
            if (self.digest) {
                CBLWarn(Database, @"Cannot access content from the blob that contains only metadata "
                        "and has no database associated with it. To access the content, "
                        "save the document first.");
            }
            [NSException raise: NSInternalInconsistencyException
                        format: @"%@", kCBLErrorMessageBlobContainsNoData];
            return nil;
        }
    }
}

- (NSInputStream*) contentStream {
    CBL_LOCK(self) {
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

+ (BOOL) isBlob:(NSDictionary<NSString *,id> *)properties {
    if (!properties[kCBLBlobDigestProperty] ||
        ![properties[kCBLBlobDigestProperty] isKindOfClass: [NSString class]] ||
        !properties[kCBLTypeProperty] || ![properties[kCBLTypeProperty] isEqual: kCBLBlobType] ||
        (properties[kCBLBlobContentTypeProperty] &&
         ![properties[kCBLBlobContentTypeProperty] isKindOfClass: [NSString class]]) ||
        (properties[kCBLBlobLengthProperty] &&
         ![properties[kCBLBlobLengthProperty] isKindOfClass: [NSNumber class]])) {
        return NO;
    }
    return YES;
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
    CBL_LOCK(self) {
        return [NSString stringWithFormat: @"%@[%@; %llu KB]",
                self.class, _contentType, (_length + 512)/1024];
    }
}

#pragma mark - Internal

- (BOOL) installInDatabase: (CBLDatabase*)db error:(NSError**)outError {
    Assert(db);
    
    CBL_LOCK(self) {
        // if the blob already has a database, skip install
        if (_db)
            return YES;
    }

    C4BlobStore *store = [db getBlobStore: outError];
    if (!store)
        return NO;

    C4Error err;
    C4BlobKey key;
    bool success = true;
    CBL_LOCK(self) {
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

- (void) checkBlobFromSameDatabase: (CBLDatabase*)database {
    CBL_LOCK(self) {
        if (_db && _db != database)
            [NSException raise: NSInternalInconsistencyException
                        format: @"%@", kCBLErrorMessageBlobDifferentDatabase];
    }
}

#pragma mark FLEECE ENCODABLE

- (id) cbl_toCBLObject {
    return self;
}

- (void) fl_encodeToFLEncoder: (FLEncoder)encoder {
    // Note: If CBLDictionary can be encoded independently of CBLDocument,
    // so there could be no extra info:
    FLEncoderContext* encContext = (FLEncoderContext*)FLEncoder_GetExtraInfo(encoder);
    
    // mark this document includs an attachment
    bool* outHasAttachment = encContext->outHasAttachment;
    if (outHasAttachment)
        *outHasAttachment = true;
    
    if (encContext->database) {
        CBLDatabase* database = encContext->database;
        [self checkBlobFromSameDatabase: database];

        CBL_LOCK(self) {
            if (self.digest) {
                // if digest is already present, assign the database and skip install
                _db = database;
            } else {
                NSError *error;
                // Note: Installing blob in the database also updates the digest property.
                if (![self installInDatabase: database error: &error]) {
                    if (encContext->encodingError) {
                        *encContext->encodingError = error;
                    }
                    return;
                }
            }
        }
    }
    
    NSDictionary* dict = [self blobProperties: encContext->encodeQueryParameter];
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
