//
//  MigrationTest.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

#import "CBLTestCase.h"

@interface MigrationTest : CBLTestCase

@end

@implementation MigrationTest


- (NSString*) databasePath: (NSString*)fileName inDirectory: (NSString*)dir {
    NSString *directory = [@"Support/databases" stringByAppendingPathComponent:dir];
    NSString* path = [[NSBundle bundleForClass: [self class]] pathForResource: fileName
                                                                       ofType: nil
                                                                  inDirectory: directory];
    Assert(path, @"FATAL: Missing file '%@' in bundle directory '%@'", fileName, directory);
    return path;
}


- (void)testMigration {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString* copiedPath = [self.directory stringByAppendingPathComponent: @"iosdb.cblite2"];
    NSError* error;
    if ([manager fileExistsAtPath: copiedPath])
        Assert([manager removeItemAtPath: copiedPath error: &error], @"Couldn't remove database file: %@", error);
    
    NSString* path = [self databasePath: @"iosdb.cblite2" inDirectory:@"ios140"];
    Assert([manager fileExistsAtPath: path]);
    
    Assert([manager copyItemAtPath: path  toPath: copiedPath error: &error], @"Couldn't copy database: %@", error);
    
    ++gC4ExpectExceptions;
    CBLDatabase* database = [[CBLDatabase alloc] initWithName: @"iosdb" config: self.db.config error: &error];
    --gC4ExpectExceptions;
    Assert(database);
    
    CBLDocument* doc1 = [database documentWithID: @"doc1"];
    Assert(doc1);
    AssertEqualObjects([doc1 stringForKey: @"type"], @"doc");
    
    CBLDictionary* attachments = [doc1 dictionaryForKey: @"_attachments"];
    Assert(attachments);
    
    CBLBlob* blob = [attachments blobForKey: @"attach1"];
    Assert(blob);
    NSString* content = [[NSString alloc] initWithData: blob.content encoding: NSUTF8StringEncoding];
    AssertEqualObjects(content, @"attach1");
    
    Assert([database delete: &error], @"Couldn't delete database");
}


@end
