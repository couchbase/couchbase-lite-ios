//
//  PerfTest.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <CouchbaseLite/CouchbaseLite.h>


@interface PerfTest : NSObject

+ (void) setResourceDirectory: (NSString*)resourceDir;

+ (void) runWithOptions: (CBLDatabaseOptions*)options;

- (instancetype) initWithDatabaseOptions: (CBLDatabaseOptions*)dbOptions;

- (instancetype) initWithDatabase: (CBLDatabase*)db;

@property (readonly, nonatomic) CBLDatabase* db;

- (NSData*) dataFromResource: (NSString*)resourceName ofType: (NSString*)type;

- (void) measureAtScale: (NSUInteger)count unit: (NSString*)unit block: (void (^)())block;

- (void) setUp;
- (void) test;
- (void) tearDown;

- (void) run;

@end
