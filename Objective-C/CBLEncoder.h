//
//  CBLEncoder.h
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

#import <Foundation/Foundation.h>
#import "CBLDatabase.h"
#import "CBLDictionary.h"

@class CBLEncoder;
@class CBLEncoderContext;

NS_ASSUME_NONNULL_BEGIN

@interface CBLEncoder : NSObject

- (nullable instancetype) initWithDB: (CBLDatabase*)db
                               error: (NSError**)error;

- (void) setExtraInfo: (CBLEncoderContext*)context;

- (void) reset;
- (nullable NSString*) getError;

- (bool) writeKey: (NSString*)key;
- (bool) write: (id)obj;

- (bool) beginArray: (NSUInteger)reserve;
- (bool) endArray;
- (bool) beginDict: (NSUInteger)reserve;
- (bool) endDict;

- (nullable NSData*) finish: (NSError**)error;

- (BOOL) finishIntoDocument: (CBLDocument*)document
                      error: (NSError**)error;

@end

@interface CBLEncoderContext : NSObject

- (instancetype) initWithDB: (CBLDatabase*)db;
- (nonnull void*) get;
- (void) reset;

@end

NS_ASSUME_NONNULL_END
