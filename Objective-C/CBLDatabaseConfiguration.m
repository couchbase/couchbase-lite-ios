//
//  CBLDatabaseConfiguration.m
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

#import "CBLDatabaseConfiguration.h"
#import "CBLDatabase+Internal.h"


@implementation CBLDatabaseConfiguration {
    BOOL _readonly;
}

@synthesize directory=_directory;

#ifdef COUCHBASE_ENTERPRISE
@synthesize encryptionKey=_encryptionKey;
#endif

- (instancetype) init {
    return [self initWithConfig: nil readonly: NO];
}


- (instancetype) initWithConfig: (nullable CBLDatabaseConfiguration*)config {
    return [self initWithConfig: config readonly: NO];
}


- (instancetype) initWithConfig: (nullable CBLDatabaseConfiguration*)config
                       readonly: (BOOL)readonly
{
    self = [super init];
    if (self) {
        _readonly = readonly;
        
        if (config) {
            _directory = config.directory;
#ifdef COUCHBASE_ENTERPRISE
            _encryptionKey = config.encryptionKey;
#endif
        } else
            _directory = [CBLDatabaseConfiguration defaultDirectory];
    }
    return self;
}


- (void) setDirectory: (NSString *)directory {
    CBLAssertNotNil(directory);
    
    [self checkReadonly];
    
    _directory = directory;
}


#pragma mark - Internal


- (void) checkReadonly {
    if (_readonly) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"This configuration object is readonly."];
    }
}


+ (NSString*) defaultDirectory {
    NSSearchPathDirectory dirID = NSApplicationSupportDirectory;
#if TARGET_OS_TV
    dirID = NSCachesDirectory; // Apple TV only allows apps to store data in the Caches directory
#endif
    NSArray* paths = NSSearchPathForDirectoriesInDomains(dirID, NSUserDomainMask, YES);
    NSString* path = paths[0];
#if !TARGET_OS_IPHONE
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    path = [path stringByAppendingPathComponent: bundleID];
#endif
    return [path stringByAppendingPathComponent: @"CouchbaseLite"];
}

@end
