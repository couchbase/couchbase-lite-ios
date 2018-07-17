//
//  CBLMockConnectionErrorLogic.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLMockConnectionErrorLogic.h"
#import "CBLMessagingError.h"
#import "CBLErrors.h"

@implementation CBLNoErrorLogic

- (BOOL)shouldCloseAtLocation:(CBLMockConnectionLifecycleLocation)location {
    return NO;
}

- (CBLMessagingError*)createError {
    return nil;
}

@end

@implementation CBLTestErrorLogic
{
    CBLMockConnectionLifecycleLocation _location;
    CBLMessagingError* _error;
    NSInteger _current;
    NSInteger _total;
}

- (instancetype)initAtLocation:(CBLMockConnectionLifecycleLocation)location withRecoveryCount:(NSInteger)recoveryCount {
    self = [super init];
    if(self) {
        if(recoveryCount <= 0) {
            _total = INT32_MAX;
            _error = [[CBLMessagingError alloc] initWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:@{@"message":@"Test Permanent Exception"}] isRecoverable:NO];
            
        } else {
            _total = recoveryCount;
            _error = [[CBLMessagingError alloc] initWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNRESET userInfo:@{@"message":@"Test Recoverable Exception"}] isRecoverable:YES];
        }
        
        _location = location;
    }
    
    return self;
}

- (BOOL)shouldCloseAtLocation:(CBLMockConnectionLifecycleLocation)location {
    return _current < _total && location == _location;
}

- (CBLMessagingError*)createError {
    _current++;
    return _error;
}

@end

@implementation CBLReconnectErrorLogic
@synthesize isErrorActive;

- (BOOL)shouldCloseAtLocation:(CBLMockConnectionLifecycleLocation)location {
    return isErrorActive;
}

- (CBLMessagingError*)createError {
    return [[CBLMessagingError alloc] initWithError:[NSError errorWithDomain:CBLErrorDomain code:-1 userInfo:@{@"message":@"Server is no longer listening"}] isRecoverable:false];
}

@end
