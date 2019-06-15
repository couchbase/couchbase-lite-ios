//
//  CBLMutableDocument.m
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

#import "CBLMutableDocument.h"
#import "CBLMutableArray.h"
#import "CBLC4Document.h"
#import "CBLData.h"
#import "CBLCoreBridge.h"
#import "CBLDocument+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CBLJSON.h"
#import "CBLMisc.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"

@implementation CBLMutableDocument
{
    NSError* _encodingError;
}

#pragma mark - Initializer

+ (instancetype) document {
    return [[self alloc] initWithID: nil];
}

+ (instancetype) documentWithID: (nullable NSString*)documentID {
    return [[self alloc] initWithID: documentID];
}

- (instancetype) init {
    return [self initWithID: nil];
}

- (instancetype) initWithID: (nullable NSString*)documentID {
    return [self initWithDatabase: nil
                       documentID: (documentID ?: CBLCreateUUID())
                            c4Doc: nil];
}

- (instancetype) initWithData: (nullable NSDictionary<NSString*,id>*)data {
    self = [self initWithID: nil];
    if (self) {
        [self setData: data];
    }
    return self;
}

- (instancetype) initWithID: (nullable NSString*)documentID
                 data: (nullable NSDictionary<NSString*,id>*)data
{
    self = [self initWithID: documentID];
    if (self) {
        [self setData: data];
    }
    return self;
}

/* internal */ - (instancetype) initAsCopyWithDocument: (CBLDocument*)doc
                                                  dict: (nullable CBLDictionary*)dict
{
    self = [self initWithDatabase: doc.database documentID: doc.id c4Doc: doc.c4Doc];
    if (self) {
        if (dict)
            _dict = [dict mutableCopy];
    }
    return self;
    
}

#pragma mark - Edit

- (CBLMutableDocument*) mutableCopyWithZone: (NSZone *)zone {
    return [[CBLMutableDocument alloc] initAsCopyWithDocument: self dict: _dict];
}

#pragma mark - CBLMutableDictionary

- (void) setValue: (nullable id)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setValue: value forKey: key];
}

- (void) setString: (nullable NSString*)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setString: value forKey: key];
}

- (void) setNumber: (nullable NSNumber*)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setNumber: value forKey: key];
}

- (void) setInteger: (NSInteger)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setInteger: value forKey: key];
}

- (void) setLongLong: (long long)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setLongLong: value forKey: key];
}

- (void) setFloat: (float)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setFloat: value forKey: key];
}

- (void) setDouble: (double)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setDouble: value forKey: key];
}

- (void) setBoolean: (BOOL)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setBoolean: value forKey: key];
}

- (void) setDate: (nullable NSDate *)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setDate: value forKey: key];
}

- (void) setBlob: (nullable CBLBlob*)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setBlob: value forKey: key];
}

- (void) setArray: (nullable CBLArray*)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setArray: value forKey: key];
}

- (void) setDictionary: (nullable CBLDictionary*)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setDictionary: value forKey: key];
}

- (void) removeValueForKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) removeValueForKey: key];
}

- (void) setData: (nullable NSDictionary<NSString *,id>*)data {
    [((CBLMutableDictionary*)_dict) setData: data];
}

#pragma mark - Internal

- (bool) isMutable {
    // CBLMutableDocument overrides this
    return true;
}

// TODO: This value is incorrect after the document is saved as self.changed
// doesn't get reset. However this is currently being used during replication's
// conflict resolution so the generation value is correct in that circumstance.
- (NSUInteger) generation {
    return super.generation + !!self.changed;
}

#pragma mark - Private

// TODO: Need to be reset after the document is saved.
- (BOOL) changed {
    return ((CBLMutableDictionary*)_dict).changed;
}

#pragma mark - Fleece Encodable

- (C4SliceResult) encode: (NSError**)outError {
    _encodingError = nil;
    auto encoder = c4db_getSharedFleeceEncoder(self.c4db);
    FLEncoder_SetExtraInfo(encoder, (__bridge void*)self);
    [_dict fl_encodeToFLEncoder: encoder];
    if (_encodingError != nil) {
        FLEncoder_Reset(encoder);
        if (outError)
            *outError = _encodingError;
        _encodingError = nil;
        return {};
    }
    FLError flErr;
    FLSliceResult body = FLEncoder_Finish(encoder, &flErr);
    if (!body.buf)
        convertError(flErr, outError);
    return body;
}

// Objects being encoded can call this
- (void) setEncodingError: (NSError*)error {
    if (!_encodingError)
        _encodingError = error;
}

@end
