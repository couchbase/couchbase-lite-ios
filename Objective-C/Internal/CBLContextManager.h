//
//  CBLContextManager.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

/**
 Thread-safe context manager for retaining and mapping the object with its pointer value which can be used as 
 the context for LiteCore's callbacks (e.g. use when creating c4queryobserver objects). The implementation
 simply stores the object in a map by using its memory address as the key and returns the memory address
 as the pointer value.
 
 @note
 There is a chance that a new registered objects may have the same memory address as the ones previously
 unregistered. This implementation can be improved to reduce a chance of reusing the same memory address
 by generating integer keys with reuseable integer number + cycle count as inspired by the implementation of
 C# GCHandle. For now, the context object MUST BE validated for its originality before use.
 */
@interface CBLContextManager : NSObject

+ (instancetype) shared;

/** Register and retain the object. The context pointer of the registered object will be returned.  */
- (void*) registerObject: (id)object;

/** Unregister the object of the given context pointer. */
- (void) unregisterObjectForPointer: (void*)ptr;

/** Get the object of the given context pointer. */
- (nullable id) objectForPointer: (void*)ptr;

/** Count number of registered objects. */
- (NSUInteger) count;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
