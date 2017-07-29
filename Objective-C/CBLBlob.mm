//
//  CBLBlob.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLBlob.h"
#import "CBLBlobStream.h"
#import "CBLDocument+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLInternal.h"
#import "CBLLog.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"
#import "c4BlobStore.h"

extern "C" {
#import "MYErrorUtils.h"
}


// Max size of data that will be cached in memory with the CBLBlob
static const size_t kMaxCachedContentLength = 8*1024;

// Stack buffer size when reading NSInputStream
static const size_t kReadBufferSize = 8*1024;

static NSString* const kTypeMetaProperty = @kC4ObjectTypeProperty;
static NSString* const kBlobType = @kC4ObjectType_Blob;


@implementation CBLBlob
{
    CBLDatabase *_db;                       // nil if blob is new and unsaved
    NSData *_content;                       // If new from data, or already loaded from db
    NSInputStream *_initialContentStream;   // If new from stream.
    NSDictionary* _properties;              // Only in blob read from database
    NSObject* _lock;                        // For thread-safety

    // A newly created unsaved blob will have either _content or _initialContentStream.
    // A new blob saved to the database will have _db and _digest.
    // A blob loaded from the database will have _db and _properties, and _digest unless invalid
}

@synthesize contentType = _contentType, length = _length, digest = _digest;


- (instancetype)initWithContentType:(NSString *)contentType
                               data:(NSData *)data
{
    Assert(data != nil);
    self = [super init];
    if(self) {
        _contentType = [contentType copy];
        _content = [data copy];
        _length = [data length];
        _lock = [[NSObject alloc] init];
    }
    
    return self;
}


- (instancetype)initWithContentType:(NSString *)contentType
                      contentStream:(NSInputStream *)stream
{
    Assert(stream != nil);
    self = [super init];
    if(self) {
        _contentType = [contentType copy];
        _initialContentStream = stream;
        _lock = [[NSObject alloc] init];
    }
    
    return self;
}


- (instancetype)initWithContentType:(NSString *)contentType
                            fileURL:(NSURL *)url
                              error:(NSError**)outError
{
    NSInputStream* stream = [[NSInputStream alloc] initWithURL: url];
    if (!stream) {
        MYReturnError(outError, NSURLErrorFileDoesNotExist, NSURLErrorDomain,
                      @"Couldn't create stream on %@", url.absoluteURL);
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

        _length = $castIf(NSNumber, _properties[@"length"]).unsignedLongLongValue;
        _digest = $castIf(NSString, _properties[@"digest"]);
        _contentType = $castIf(NSString, _properties[@"content-type"]);
        if (!_digest) {
            C4Warn("Blob read from database has missing digest");
            _digest = @"";
        }
    }
    return self;
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@; %llu KB]",
            self.class, _contentType, (_length + 512)/1024];
}


- (NSDictionary *)properties {
    if (_properties) {
        // Blob read from database;
        return _properties;
    } else {
        // New blob:
        CBL_LOCK(_lock) {
            return $dict({@"digest", _digest},
                         {@"length", (_length ? @(_length) : nil)},
                         {@"content-type", _contentType});
        }
    }
}


- (NSDictionary *)jsonRepresentation {
    Assert(_db, @"Blob hasn't been saved in the database yet");
    NSMutableDictionary *json = [self.properties mutableCopy];
    json[kTypeMetaProperty] = kBlobType;
    return json;
}


- (BOOL) getBlobStore: (C4BlobStore**)outBlobStore andKey: (C4BlobKey*)outBlobKey {
    *outBlobStore = [_db getBlobStore: nil]; // thread-safe
    return *outBlobStore && _digest && c4blob_keyFromString(CBLStringBytes(_digest), outBlobKey);
}


- (NSData *)content {
    CBL_LOCK(_lock) {
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
            Assert(_initialContentStream);
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


- (uint64_t) length {
    CBL_LOCK(_lock) {
        return _length;
    }
}


- (NSString*) digest {
    CBL_LOCK(_lock) {
        return _digest;
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


- (BOOL) installInDatabase: (CBLDatabase *)db error:(NSError **)outError {
    Assert(db);
    if (_db) {
        Assert(_db == db, @"Blob belongs to a different database");
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


- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError
{
    CBL_LOCK(_lock) {
        if(![self installInDatabase: database error: outError])
            return NO;
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
    return YES;
}


@end
