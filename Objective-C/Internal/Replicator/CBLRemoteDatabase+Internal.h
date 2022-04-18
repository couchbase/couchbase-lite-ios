//
//  CBLRemoteDatabase+Internal.h
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

#import "CBLRemoteDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface ConnectedClientContext : NSObject
@property (nonatomic) CBLRemoteDatabase* remoteDB;

- (instancetype) init NS_UNAVAILABLE;
- (instancetype) initWithRemoteDB: (CBLRemoteDatabase*)db;
@end

@implementation ConnectedClientContext
@synthesize remoteDB=_remoteDB;

- (instancetype) initWithRemoteDB: (CBLRemoteDatabase*)db {
    self = [super init];
    if (self) {
        _remoteDB = db;
    }
    return self;
}

@end

@interface ConnectedClientGetDocumentContext : ConnectedClientContext
@property (nonatomic) void(^docGetCompletion)(CBLDocument*, NSError*);

- (instancetype) init NS_UNAVAILABLE;
- (instancetype) initWithRemoteDB: (CBLRemoteDatabase*)db
                       completion: (void(^)(CBLDocument*, NSError*))completion;
@end

@implementation ConnectedClientGetDocumentContext
@synthesize docGetCompletion=_docGetCompletion;


- (instancetype) initWithRemoteDB: (CBLRemoteDatabase *)db
                       completion: (void (^)(CBLDocument *, NSError *))completion {
    self = [super initWithRemoteDB: db];
    if (self) {
        _docGetCompletion = completion;
    }
    return self;
}

@end

@interface ConnectedClientPutDocumentContext : ConnectedClientContext
@property (nonatomic) NSString* docID;
@property (nonatomic) FLSliceResult docBody;
@property (nonatomic) BOOL isDeleted;
@property (nonatomic) void(^docUpdateCompletion)(CBLDocument* _Nullable, NSError*);

- (instancetype) init NS_UNAVAILABLE;

- (instancetype) initWithRemoteDB: (CBLRemoteDatabase*)db
                            docID: (nullable NSString*)docID
                          docBody: (FLSliceResult)docBody
                        isDeleted: (BOOL)isDeleted
                       completion: (void(^)(CBLDocument* _Nullable, NSError*))completion;
@end

@implementation ConnectedClientPutDocumentContext

@synthesize docUpdateCompletion=_docUpdateCompletion, docID=_docID, docBody=_docBody;
@synthesize isDeleted=_isDeleted;

- (instancetype) initWithRemoteDB: (CBLRemoteDatabase *)db
                            docID: (nullable NSString*)docID
                          docBody: (FLSliceResult)docBody
                        isDeleted: (BOOL)isDeleted
                       completion: (void (^)(CBLDocument* _Nullable, NSError*))completion {
    self = [super initWithRemoteDB: db];
    if (self) {
        if (isDeleted) {
            _isDeleted = isDeleted;
        } else {
            _docID = docID;
            _docBody = FLSliceResult_Retain(docBody);
        }
        _docUpdateCompletion = completion;
    }
    return self;
}

- (void) dealloc {
    if (_docBody.buf)
        FLSliceResult_Release(_docBody);
}

@end

NS_ASSUME_NONNULL_END
