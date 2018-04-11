//
//  CBLDatabase+EncryptionInternal.h
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
#import "CBLDatabase.h"
#import "c4.h"
@class CBLEncryptionKey;

#ifndef COUCHBASE_ENTERPRISE
#error Couchbase Lite EE Only
#endif

NS_ASSUME_NONNULL_BEGIN

@interface CBLDatabase (EncryptionInternal)

+ (C4EncryptionKey) c4EncryptionKey: (nullable CBLEncryptionKey*)key;

@end

NS_ASSUME_NONNULL_END
