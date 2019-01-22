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

using namespace cbl;

extern "C" {
#import "MYErrorUtils.h"
}


// Max size of data that will be cached in memory with the CBLBlob
static const size_t kMaxCachedContentLength = 8*1024;

// Stack buffer size when reading NSInputStream
static const size_t kReadBufferSize = 8*1024;

static NSString* const kTypeMetaProperty = @kC4ObjectTypeProperty;
static NSString* const kDataMetaProperty = @kC4BlobDataProperty;
static NSString* const kBlobType = @kC4ObjectType_Blob;


@implementation CBLBlob
{
    CBLDatabase *_db;                       // nil if blob is new and unsaved
    NSData *_content;                       // If new from data, or already loaded from db
    NSInputStream *_initialContentStream;   // If new from stream.
    NSDictionary* _properties;              // Only in blob read from database

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
    Assert(url.isFileURL, @"url must be a file-based URL");
    
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
        NSMutableDictionary *tempProps = [properties mutableCopy];
        tempProps[kTypeMetaProperty] = nil;
        _properties = tempProps;

        _length = asNumber(_properties[@"length"]).unsignedLongLongValue;
        _digest = asString(_properties[@"digest"]);
        _contentType = asString(_properties[@"content_type"]);
        _content = asData(_properties[kDataMetaProperty]);
        if (!_digest && !_content) {
            C4Warn("Blob read from database has missing digest");
            _digest = @"";
        }
    }
    return self;
}


- (NSDictionary *)properties {
    if (_properties) {
        // Blob read from database;
        return _properties;
    } else {
        // New blob:
        return $dict({@"digest", _digest},
                     {@"length", (_length ? @(_length) : nil)},
                     {@"content_type", _contentType});
    }
}


- (NSDictionary *)jsonRepresentation {
    NSMutableDictionary *json = [self.properties mutableCopy];
    json[kTypeMetaProperty] = kBlobType;
    return json;
}


- (BOOL) getBlobStore: (C4BlobStore**)outBlobStore andKey: (C4BlobKey*)outBlobKey {
    *outBlobStore = [_db getBlobStore: nullptr];
    return *outBlobStore && _digest && c4blob_keyFromString(CBLStringBytes(_digest), outBlobKey);
}


- (NSData *)content {
    if(_content != nil) {
        // Data is in memory:
        return _content;
    } else if (_db) {
        // Read blob from the BlobStore:
        C4BlobStore *blobStore;
        C4BlobKey key;
        if (![self getBlobStore: &blobStore andKey: &key])
            return nil;
        //TODO: If data is large, can get the file path & memory-map it
        NSData* content = sliceResult2data(c4blob_getContents(blobStore, key, nullptr));
        if (content && content.length <= kMaxCachedContentLength)
            _content = content;
        return content;
    } else {
        // No recourse but to read the initial stream into memory:
        if (!_initialContentStream) {
            [NSException raise: NSInternalInconsistencyException
                    format: @"Blob has no data available"];
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


- (NSInputStream *)contentStream {
    if (_db) {
        C4BlobStore *blobStore;
        C4BlobKey key;
        if (![self getBlobStore: &blobStore andKey: &key])
            return nil;
        return [[CBLBlobStream alloc] initWithStore: blobStore key: key];
    } else {
        NSData* content = self.content;
        return content ? [[NSInputStream alloc] initWithData: content] : nil;
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
    return [NSString stringWithFormat: @"%@[%@; %llu KB]",
            self.class, _contentType, (_length + 512)/1024];
}


#pragma mark - Internal


- (BOOL) installInDatabase: (CBLDatabase *)db error:(NSError **)outError {
    Assert(db);
    if (_db) {
        if (_db != db) {
            [NSException raise: NSInternalInconsistencyException
                        format: @"A document contains a blob that was saved "
                                 "to a different database; the save operation cannot complete"];
        }
        return YES;
    }

    C4BlobStore *store = [db getBlobStore: outError];
    if (!store)
        return NO;

    C4Error err;
    C4BlobKey key;
    bool success = true;
    if (_content) {
        success = c4blob_create(store, data2slice(_content), nullptr, &key, &err);
    } else {
        Assert(_initialContentStream);
        C4WriteStream* blobOut = c4blob_openWriteStream(store, &err);
        if(!blobOut)
            return convertError(err, outError);

        uint8_t buffer[kReadBufferSize];
        NSInteger bytesRead = 0;
        _length = 0;
        NSInputStream *contentStream = [self contentStream];
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
    
    if (!document) {
        CBLStringBytes bKey(kDataMetaProperty);
        FLEncoder_WriteKey(encoder, bKey);
        FLEncoder_WriteNSObject(encoder, self.content);
    }
    
    FLEncoder_EndDict(encoder);
}

@end
