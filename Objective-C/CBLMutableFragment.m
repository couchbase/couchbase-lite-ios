//
//  CBLMutableFragment.m
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

#import "CBLMutableFragment.h"
#import "CBLDocument+Internal.h"


@implementation CBLMutableFragment


- (void) setValue: (NSObject*)value {
    if (_key)
        [_parent setValue: value forKey: _key];
    else
        [_parent setValue: value atIndex: _index];
}


- (void) setString: (NSString *)value {
    if (_key)
        [_parent setString: value forKey: _key];
    else
        [_parent setString: value atIndex: _index];
}


- (void) setNumber: (NSNumber *)value {
    if (_key)
        [_parent setNumber: value forKey: _key];
    else
        [_parent setNumber: value atIndex: _index];
}


- (void) setIntegerValue: (NSInteger)value {
    if (_key)
        [_parent setInteger: value forKey: _key];
    else
        [_parent setInteger: value atIndex: _index];
}


- (void) setLongLongValue: (long long)value {
    if (_key)
        [_parent setLongLong: value forKey: _key];
    else
        [_parent setLongLong: value atIndex: _index];
}


- (void) setFloatValue: (float)value {
    if (_key)
        [_parent setFloat: value forKey: _key];
    else
        [_parent setFloat: value atIndex: _index];
}


- (void) setDoubleValue: (double)value {
    if (_key)
        [_parent setDouble: value forKey: _key];
    else
        [_parent setDouble: value atIndex: _index];
}


- (void) setBooleanValue: (BOOL)value {
    if (_key)
        [_parent setBoolean: value forKey: _key];
    else
        [_parent setBoolean: value atIndex: _index];
}


- (void) setDate: (NSDate*)value {
    if (_key)
        [_parent setDate: value forKey: _key];
    else
        [_parent setDate: value atIndex: _index];
}


- (void) setBlob: (CBLBlob*)value {
    if (_key)
        [_parent setBlob: value forKey: _key];
    else
        [_parent setBlob: value atIndex: _index];
}


- (void) setArray: (CBLMutableArray*)value {
    if (_key)
        [_parent setArray: value forKey: _key];
    else
        [_parent setArray: value atIndex: _index];
}


- (void) setDictionary: (CBLMutableDictionary*)value {
    if (_key)
        [_parent setDictionary: value forKey: _key];
    else
        [_parent setDictionary: value atIndex: _index];
}


@end
