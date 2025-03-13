//
//  CBLEncoder.mm
//  CouchbaseLite
//
//  Created by Callum Birks on 10/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
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
    std::unique_ptr<C4Transaction> _transaction;
    NSError* _error;
}

- (nullable instancetype)initWithDB:(nonnull CBLDatabase *)db error:(NSError**)error {
    self = [super init];
    if (self) {
        _encoder = c4db_getSharedFleeceEncoder(db.c4db);
        _db = db;
        _transaction = std::make_unique<C4Transaction>(db.c4db);
        if (!_transaction->begin()) {
            convertError(_transaction->error(), error);
            return nil;
        }
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

- (nullable NSData *)finish {
    C4SliceResult data = FLEncoder_Finish(_encoder, nullptr);
    _transaction->end(true);
    return sliceResult2data(data);
}

- (bool)finishInto:(CBLDocument *)document {
    FLDoc fldoc = FLEncoder_FinishDoc(_encoder, nullptr);
    Doc doc { fldoc };
    Dict fleeceData = doc.asDict();
    _transaction->end(true);
    if (!fleeceData) {
        return false;
    }
    [document setFleece: (FLDict)fleeceData];
    return true;
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
        _context = { .database = _database, .encodingError = _error, .outHasAttachment = &_hasAttachment };
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

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    return [[[self class] alloc] initWithDB: _database];
}

@end
