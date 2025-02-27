//
//  CBLEncoder.mm
//  CouchbaseLite
//
//  Created by Callum Birks on 10/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

#import "fleece/Fleece.hh"
#import "CBLEncoder.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLDatabase+Internal.h"

@implementation CBLEncoder {
    std::unique_ptr<fleece::Encoder> _encoder;
}

- (instancetype)init {
    self = [super init];
    return self;
}

- (instancetype) initWithFLEncoder:(FLEncoder)enc {
    self = [super init];
    if (self) {
        _encoder = std::make_unique<fleece::Encoder>(enc);
    }
    return self;
}

- (nonnull instancetype)initWithSharedKeys:(nonnull FLSharedKeys)sk {
    self = [super init];
    if (self) {
        _encoder = std::make_unique<fleece::Encoder>(sk);
    }
    return self;
}

- (nonnull instancetype)initWithDB:(nonnull CBLDatabase *)db {
    self = [super init];
    if (self) {
        auto shared = c4db_getSharedFleeceEncoder(db.c4db);
        _encoder = std::make_unique<fleece::Encoder>(shared);
    }
    return self;
}

- (bool)beginArray:(NSUInteger)reserve {
    return _encoder->beginArray(reserve);
}

- (bool)beginDict:(NSUInteger)reserve { 
    return _encoder->beginDict(reserve);
}

- (bool)endArray { 
    return _encoder->endArray();
}

- (bool)endDict { 
    return _encoder->endDict();
}

- (nullable NSData *)finish { 
    auto r = _encoder->finish();
    auto sr = C4SliceResult { r.buf, r.size };
    return sliceResult2data(sr);
}

- (void)reset { 
    _encoder.reset();
}

- (NSString*)getError {
    const char *cstr = _encoder->errorMessage();
    if (cstr == NULL) {
        return nil;
    }
    NSString *str = [[NSString alloc] initWithCString: cstr encoding: NSUTF8StringEncoding];
    return str;
}

- (bool)write:(nonnull id)obj { 
    return _encoder->writeNSObject(obj);
}

- (bool)writeKey:(nonnull NSString *)key {
    return _encoder->writeKey(c4str(key.UTF8String));
}


- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    return [[[self class] alloc] initWithFLEncoder: _encoder->operator _FLEncoder *()];
}

@end
