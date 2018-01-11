//
//  CBLDatabaseConfiguration.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDatabaseConfiguration.h"
#import "CBLDatabase+Internal.h"

@interface CBLDatabaseConfigurationBuilder()
- (instancetype) initWithConfig: (nullable CBLDatabaseConfiguration*)config;
@end

@implementation CBLDatabaseConfigurationBuilder

@synthesize directory=_directory;
@synthesize conflictResolver = _conflictResolver;
@synthesize encryptionKey=_encryptionKey;
@synthesize fileProtection=_fileProtection;

- (instancetype) initWithConfig: (nullable CBLDatabaseConfiguration*)config {
    self = [super init];
    if (self) {
        if (config) {
            _directory = config.directory;
            _conflictResolver = config.conflictResolver;
            _encryptionKey = config.encryptionKey;
            _fileProtection = config.fileProtection;
        }
    }
    return self;
}


- (NSString*) directory {
    if (!_directory)
        _directory = [CBLDatabaseConfiguration defaultDirectory];
    return _directory;
}


- (id<CBLConflictResolver>) conflictResolver {
    if (!_conflictResolver)
        _conflictResolver = [[CBLDefaultConflictResolver alloc] init];
    return _conflictResolver;
}

@end

@implementation CBLDatabaseConfiguration

@synthesize directory=_directory;
@synthesize conflictResolver = _conflictResolver;
@synthesize encryptionKey=_encryptionKey;
@synthesize fileProtection=_fileProtection;


- (instancetype) init {
    return [self initWithConfig: nil block: nil];
}


- (instancetype) initWithBlock: (nullable void(^)(CBLDatabaseConfigurationBuilder* builder))block
{
    return [self initWithConfig: nil block: block];
}


- (instancetype) initWithConfig: (nullable CBLDatabaseConfiguration*)config
                          block: (nullable void(^)(CBLDatabaseConfigurationBuilder* builder))block
{
    self = [super init];
    if (self) {
        CBLDatabaseConfigurationBuilder* builder =
            [[CBLDatabaseConfigurationBuilder alloc] initWithConfig: config];
        
        if (block)
            block(builder);
        
        _directory = builder.directory;
        _conflictResolver = builder.conflictResolver;
        _encryptionKey = builder.encryptionKey;
        _fileProtection = builder.fileProtection;
    }
    return self;
}


#pragma mark - Internal


+ (NSString*) defaultDirectory {
    NSSearchPathDirectory dirID = NSApplicationSupportDirectory;
#if TARGET_OS_TV
    dirID = NSCachesDirectory; // Apple TV only allows apps to store data in the Caches directory
#endif
    NSArray* paths = NSSearchPathForDirectoriesInDomains(dirID, NSUserDomainMask, YES);
    NSString* path = paths[0];
#if !TARGET_OS_IPHONE
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSCAssert(bundleID, @"No bundle ID");
    path = [path stringByAppendingPathComponent: bundleID];
#endif
    return [path stringByAppendingPathComponent: @"CouchbaseLite"];
}


@end

