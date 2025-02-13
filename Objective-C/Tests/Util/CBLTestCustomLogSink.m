//
//  CBLTestCustomLogSink.m
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

#import "CBLTestCustomLogSink.h"

@implementation CBLTestCustomLogSink {
    NSMutableArray* _lines;
}

- (instancetype) init {
    self = [super init];
    if (self) {
        _lines = [NSMutableArray new];
    }
    return self;
}

- (NSArray*) lines {
    return _lines;
}

- (BOOL) containsString: (NSString *)string {
    for (NSString* line in _lines) {
        if ([line containsString: string]) {
            return YES;
        }
    }
    return NO;
}

- (void) reset {
    [_lines removeAllObjects];
}

- (void) writeLogWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
    [_lines addObject: message];
}

@end
