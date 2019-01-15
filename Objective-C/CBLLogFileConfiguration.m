//
//  CBLLogFileConfiguration.m
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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


#import "CBLLogFileConfiguration+Internal.h"

#define kCBLLogFileConfigurationDefaultMaxSize 500*1024

@implementation CBLLogFileConfiguration {
    BOOL _readonly;
}

@synthesize directory=_directory, usePlainText=_usePlainText;
@synthesize maxSize=_maxSize, maxRotateCount=_maxRotateCount;


- (instancetype) initWithDirectory: (NSString*)directory {
    self = [super init];
    if (self) {
        CBLAssertNotNil(directory);
        _readonly = NO;
        _directory = directory;
        _maxSize = kCBLLogFileConfigurationDefaultMaxSize;
        _maxRotateCount = 1;
    }
    return self;
}


- (instancetype) initWithConfig: (CBLLogFileConfiguration*)config
                       readonly: (BOOL)readonly {
    self = [super init];
    if (self) {
        _readonly = readonly;
        _directory = config.directory;
        _usePlainText = config.usePlainText;
        _maxSize = config.maxSize;
        _maxRotateCount = config.maxRotateCount;
    }
    return self;
}


- (void) setUsePlainText: (BOOL)usePlainText {
    [self checkReadonly];
    _usePlainText = usePlainText;
}


- (void) setMaxSize: (uint64_t)maxSize {
    [self checkReadonly];
    _maxSize = maxSize;
}


- (void) setMaxRotateCount: (NSInteger)maxRotateCount {
    [self checkReadonly];
    _maxRotateCount = maxRotateCount;
}


#pragma mark - Internal


- (void) checkReadonly {
    if (_readonly) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"This configuration object is readonly."];
    }
}


@end
