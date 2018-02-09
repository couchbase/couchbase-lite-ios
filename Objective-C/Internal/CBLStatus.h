//
//  CBLStatus.h
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

#pragma once
#import <Foundation/Foundation.h>
#import "CBLErrors.h"
#import "Fleece.h"
#import "c4.h"

NS_ASSUME_NONNULL_BEGIN

BOOL convertError(const C4Error &error, NSError* _Nullable * outError);

BOOL convertError(const FLError &error, NSError* _Nullable * outError);

// Converts an NSError back to a C4Error (used by the WebSocket implementation)
void convertError(NSError* error, C4Error *outError);

BOOL createError(int status, NSError* _Nullable * outError);

BOOL createError(int status, NSString  * _Nullable  desc, NSError* _Nullable * outError);

NS_ASSUME_NONNULL_END
