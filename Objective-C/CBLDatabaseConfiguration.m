//
//  CBLDatabaseConfiguration.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDatabaseConfiguration.h"
#import "CBLDatabase+Internal.h"

@implementation CBLDatabaseConfiguration

@synthesize directory=_directory;
@synthesize conflictResolver = _conflictResolver;
@synthesize encryptionKey=_encryptionKey;
@synthesize fileProtection=_fileProtection;


- (instancetype) init {
    return [super init];
}


- (instancetype) copyWithZone:(NSZone *)zone {
    CBLDatabaseConfiguration* o = [[self.class alloc] init];
    o.directory = _directory;
    o.conflictResolver = _conflictResolver;
    o.encryptionKey = _encryptionKey;
    o.fileProtection = _fileProtection;
    return o;
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
