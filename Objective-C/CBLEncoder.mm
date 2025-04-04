//
//  CBLEncoder.mm
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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

#import "fleece/Fleece.hh"
#import "CBLFleece.hh"
#import "MRoot.hh"
#import "CBLEncoder.h"
#import "CBLCoreBridge.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"

using namespace fleece;

@implementation CBLEncoder {
    FLEncoder _encoder;
    CBLDatabase* _db;
    NSError* _error;
}

- (nullable instancetype)initWithDB:(nonnull CBLDatabase *)db error:(NSError**)error {
    self = [super init];
    if (self) {
        _encoder = c4db_getSharedFleeceEncoder(db.c4db);
        _db = db;
    }
    return self;
}

- (void)setExtraInfo:(CBLEncoderContext *)context {
    void* flcontext = [context get];
    FLEncoder_SetExtraInfo(_encoder, flcontext);
}

- (bool)beginArray:(NSUInteger)reserve {
    return FLEncoder_BeginArray(_encoder, reserve);
}

- (bool)beginDict:(NSUInteger)reserve { 
    return FLEncoder_BeginDict(_encoder, reserve);
}

- (bool)endArray { 
    return FLEncoder_EndArray(_encoder);
}

- (bool)endDict { 
    return FLEncoder_EndDict(_encoder);
}

- (nullable NSData *)finish:(NSError**)outError {
    FLError error {};
    C4SliceResult data = FLEncoder_Finish(_encoder, &error);
    if (!data) {
        convertError(error, outError);
        return nil;
    }
    return sliceResult2data(data);
}

- (BOOL)finishIntoDocument:(CBLDocument*)document error:(NSError**)outError {
    FLError error {};
    FLDoc fldoc = FLEncoder_FinishDoc(_encoder, &error);
    if (!fldoc) {
        return convertError(error, outError);
    }
    Doc doc { fldoc };
    Dict fleeceData = doc.asDict();
    if (!fleeceData) {
        return NO;
    }
    [document setFleece: (FLDict)fleeceData];
    return YES;
}

- (void)reset {
    FLEncoder_Reset(_encoder);
}

- (NSString*)getError {
    const char *cstr = FLEncoder_GetErrorMessage(_encoder);
    if (cstr == NULL) {
        return nil;
    }
    NSString *str = [[NSString alloc] initWithCString: cstr encoding: NSUTF8StringEncoding];
    return str;
}

- (bool)write:(nonnull id)obj {
    return FLEncoder_WriteNSObject(_encoder, obj);
}

- (bool)writeKey:(nonnull NSString *)key {
    return FLEncoder_WriteKey(_encoder, c4str(key.UTF8String));
}

@end

@implementation CBLEncoderContext {
    CBLDatabase* _database;
    NSError* _error;
    bool _hasAttachment;
    FLEncoderContext _context;
}

- (instancetype) initWithDB:(CBLDatabase *)db {
    self = [super init];
    if (self) {
        _database = db;
        _error = nil;
        _hasAttachment = false;
        _context = { .database = _database, .encodingError = &_error, .outHasAttachment = &_hasAttachment };
    }
    return self;
}

- (nonnull void*)get {
    return &_context;
}

- (void) reset {
    _error = nil;
    _hasAttachment = false;
}

@end
