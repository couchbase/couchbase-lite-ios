//
//  CBLMutableDocument.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLMutableDocument.h"
#import "CBLMutableArray.h"
#import "CBLC4Document.h"
#import "CBLConflictResolver.h"
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


- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary {
    self = [self initWithID: nil];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


- (instancetype) initWithID: (nullable NSString*)documentID
                 dictionary: (NSDictionary<NSString*,id>*)dictionary
{
    self = [self initWithID: documentID];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


/* internal */ - (instancetype) initWithDocument: (CBLDocument*)doc {
    return [self initWithDatabase: doc.database
                       documentID: doc.id
                            c4Doc: doc.c4Doc];
    
}

#pragma mark - Edit

- (CBLMutableDocument*) mutableCopyWithZone:(NSZone *)zone {
    return [[CBLMutableDocument alloc] initWithDocument: self];
}

- (CBLMutableDocument*) edit {
    return self;
}


#pragma mark - CBLMutableDictionary


- (void) setArray: (nullable CBLArray *)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setArray: value forKey: key];
}


- (void) setBoolean: (BOOL)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setBoolean: value forKey: key];
}


- (void) setBlob: (nullable CBLBlob*)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setBlob: value forKey: key];
}


- (void) setDate: (nullable NSDate *)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setDate: value forKey: key];
}


- (void) setDictionary: (nullable CBLDictionary *)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setDictionary: value forKey: key];
}


- (void) setDouble: (double)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setDouble: value forKey: key];
}


- (void) setFloat: (float)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setFloat: value forKey: key];
}


- (void) setInteger: (NSInteger)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setInteger: value forKey: key];
}


- (void) setLongLong: (long long)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setLongLong: value forKey: key];
}


- (void) setNumber: (nullable NSNumber*)value forKey: (NSString *)key {
    [self setNumber: value forKey: key];
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    [((CBLMutableDictionary*)_dict) setObject: value forKey: key];
}


- (void) setString: (nullable NSString *)value forKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) setString: value forKey: key];
}


- (void) removeObjectForKey: (NSString *)key {
    [((CBLMutableDictionary*)_dict) removeObjectForKey: key];
}


- (void) setDictionary: (NSDictionary<NSString *,id> *)dictionary {
    [((CBLMutableDictionary*)_dict) setDictionary: dictionary];
}


#pragma mark - Internal


- (bool) isMutable {
    // CBLMutableDocument overrides this
    return true;
}


- (NSUInteger) generation {
    return super.generation + !!self.changed;
}


#pragma mark - Private


// Reflects only direct changes to the document. Changes on sub dictionaries or arrays will
// not be propagated here.
- (BOOL) changed {
    return ((CBLMutableDictionary*)_dict).changed;
}


#pragma mark - Fleece Encodable


- (NSData*) encode: (NSError**)outError {
    _encodingError = nil;
    auto encoder = c4db_getSharedFleeceEncoder(self.c4db);
    FLEncoder_SetExtraInfo(encoder, (__bridge void*)self);
    [_dict fl_encodeToFLEncoder: encoder];
    if (_encodingError != nil) {
        FLEncoder_Reset(encoder);
        if (outError)
            *outError = _encodingError;
        _encodingError = nil;
        return nil;
    }
    FLError flErr;
    FLSliceResult body = FLEncoder_Finish(encoder, &flErr);
    if (!body.buf)
        convertError(flErr, outError);
    return sliceResult2data(body);
}


// Objects being encoded can call this
- (void) setEncodingError: (NSError*)error {
    if (!_encodingError)
        _encodingError = error;
}


@end
