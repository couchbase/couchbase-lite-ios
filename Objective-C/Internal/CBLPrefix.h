//
//  CBLPrefix.h
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

#ifdef __OBJC__

#import <Foundation/Foundation.h>

#import "Fleece.h"
#import "CBLLog.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef CBL_THREADSAFE
#define CBL_THREADSAFE 1
#endif

#import "CBLException.h"
#import "CBLLock.h"
#import "CollectionUtils.h"
#import "Test.h"

#ifdef __cplusplus
}
#endif

#endif // __OBJC__
