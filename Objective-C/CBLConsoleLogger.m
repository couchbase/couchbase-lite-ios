//
//  CBLConsoleLogger.m
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

#import "CBLConsoleLogger.h"
#import "CBLLog+Internal.h"
#import "CBLLog+Admin.h"

@implementation CBLConsoleLogger

@synthesize level=_level, domains=_domains;

- (instancetype) initWithLogLevel: (CBLLogLevel)level {
    self = [super init];
    if (self) {
        _level = level;
        _domains = kCBLLogDomainAll;
    }
    return self;
}


- (void) setLevel: (CBLLogLevel)level {
    _level = level;
    [[CBLLog sharedInstance] synchronizeCallbackLogLevel];
}


- (void) logWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString *)message {
    if (self.level > level || (self.domains & domain) == 0)
        return;
    
    NSString* levelName = CBLLog_GetLevelName(level);
    NSString* domainName = CBLLog_GetDomainName(domain);
    NSLog(@"CouchbaseLite %@ %@: %@", domainName, levelName, message);
}

@end
