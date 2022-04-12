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
#import "CBLFleece.hh"

using namespace fleece;

@implementation CBLMutableDocument

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
                       documentID: (documentID ?: [self generateID])
                            c4Doc: nil];
}

- (instancetype) initWithData: (NSDictionary<NSString*,id>*)data {
    self = [self initWithID: nil];
    if (self) {
        [self setData: data];
    }
    return self;
}

- (instancetype) initWithID: (nullable NSString*)documentID
                       data: (NSDictionary<NSString*,id>*)data
{
    self = [self initWithID: documentID];
    if (self) {
        [self setData: data];
    }
    return self;
}

- (instancetype) initWithJSON: (NSString*)json
                        error: (NSError**)error {
    self = [self initWithID: nil];
    if (self) {
        if (![self setJSON: json error: error])
            return nil;
    }
    return self;
}

- (instancetype) initWithID: (nullable NSString*)documentID
                       json: (NSString*)json
                      error: (NSError**)error {
    self = [self initWithID: documentID];
    if (self) {
        if (![self setJSON: json error: error])
            return nil;
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

// This is used by ConnectedClient API
// Used to convert a CBLDocument to CBLMutableDocument
- (instancetype) initAsCopyOfRemoteDB: (CBLDocument*)doc {
    return [self initWithDocumentID: doc.id revisionID: doc.revisionID body: doc.remoteDocBody];
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

- (void) setData: (NSDictionary<NSString *,id>*)data {
    [((CBLMutableDictionary*)_dict) setData: data];
}

- (BOOL) setJSON: (NSString*)json error: (NSError**)error {
    return [((CBLMutableDictionary*)_dict) setJSON: json error: error];
}

- (NSString*) toJSON {
    // Overrides CBLDocument
    [NSException raise: NSInternalInconsistencyException
                format: @"toJSON on Mutable objects are unsupported"];
    return nil;
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

- (NSString*) generateID {
    char docID[kC4GeneratedIDLength + 1];
    c4doc_generateID(docID, sizeof(docID));
    return slice(docID).asNSString();
}

#pragma mark - Private

// TODO: Need to be reset after the document is saved.
- (BOOL) changed {
    return ((CBLMutableDictionary*)_dict).changed;
}

@end
