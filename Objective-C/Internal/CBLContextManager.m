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

#import "CBLContextManager.h"

@implementation CBLContextManager {
    NSMutableDictionary* _contextMap;
}

+ (CBLContextManager*) shared {
    static CBLContextManager* shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype) init {
    self = [super init];
    if (self) {
        _contextMap = [NSMutableDictionary dictionaryWithCapacity: 20];
    }
    return self;
}

- (void*) registerObject: (id)object {
    CBL_LOCK(self) {
        void* ptr = (__bridge void *)(object);
        [_contextMap setObject: object forKey: [NSValue valueWithPointer: ptr]];
        return ptr;
    }
}

- (void) unregisterObjectForPointer: (void*)ptr {
    CBL_LOCK(self) {
        [_contextMap removeObjectForKey: [NSValue valueWithPointer: ptr]];
    }
}

- (id) objectForPointer: (void*)ptr {
    CBL_LOCK(self) {
        return [_contextMap objectForKey: [NSValue valueWithPointer: ptr]];
    }
}

- (NSUInteger) count {
    CBL_LOCK(self) {
        return [_contextMap count];
    }
}

@end
