//
//  CBLDatabaseConfiguration.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDatabaseConfiguration.h"
#import "CBLDatabase+Internal.h"


@implementation CBLDatabaseConfiguration {
    BOOL _readonly;
}

@synthesize directory=_directory;
@synthesize conflictResolver =_conflictResolver;
@synthesize encryptionKey=_encryptionKey;


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
            _conflictResolver = config.conflictResolver;
            _encryptionKey = config.encryptionKey;
        } else {
            _directory = [CBLDatabaseConfiguration defaultDirectory];
            _conflictResolver = [[CBLDefaultConflictResolver alloc] init];
        }
    }
    return self;
}


- (void) setDirectory: (NSString *)directory {
    [self checkReadonly];
    
    if (_directory != directory) {
        _directory = directory;
    }
}


- (void) setConflictResolver: (id<CBLConflictResolver>)conflictResolver {
    [self checkReadonly];
    
    if (_conflictResolver != conflictResolver) {
        _conflictResolver = conflictResolver;
    }
}


- (void) setEncryptionKey: (CBLEncryptionKey *)encryptionKey {
    [self checkReadonly];
    
    if (_encryptionKey != encryptionKey) {
        _encryptionKey = encryptionKey;
    }
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
