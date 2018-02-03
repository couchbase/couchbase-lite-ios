//
//  SampleCodeTest.m
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

@interface SampleCodeTest : CBLTestCase

@end

@implementation SampleCodeTest

#pragma mark - Database

- (void) dontTestNewDatabase {
    // <doc>
    NSError *error;
    CBLDatabase *database = [[CBLDatabase alloc] initWithName:@"my-database" error:&error];
    if (!database) {
        NSLog(@"Cannot open the database: %@", error);
    }
    // </doc>
}

- (void) dontTestEncryption {
    // <doc>
    CBLDatabaseConfiguration *config = [[CBLDatabaseConfiguration alloc] init];
    config.encryptionKey = [[CBLEncryptionKey alloc] initWithPassword:@"secretpassword"];
    
    NSError *error;
    CBLDatabase *database = [[CBLDatabase alloc] initWithName:@"my-database" config: config error:&error];
    if (!database) {
        NSLog(@"Cannot open the database: %@", error);
    }
    // </doc>
}

- (void) dontTestLogging {
    // <doc>
    [CBLDatabase setLogLevel: kCBLLogLevelVerbose domain: kCBLLogDomainReplicator];
    [CBLDatabase setLogLevel: kCBLLogLevelVerbose domain: kCBLLogDomainQuery];
    // </doc>
}

- (void) dontTestLoadingPrebuilt {
    // <doc>
    if (![CBLDatabase databaseExists:@"travel-sample" inDirectory:nil]) {
        NSError*error;
        NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"travel-sample" ofType:@"cblite2"];
        if (![CBLDatabase copyFromPath:path toDatabase:@"travel-sample" withConfig:nil error:&error]) {
            [NSException raise:NSInternalInconsistencyException
                        format:@"Could not load pre-built database: %@", error];
        }
    }
    // </doc>
}

#pragma mark - Document

- (void) dontTestInitializer {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    NSDictionary *dict = @{@"type": @"task",
                           @"owner": @"todo",
                           @"createdAt": [NSDate date]};
    CBLMutableDocument *newTask = [[CBLMutableDocument alloc] initWithData:dict];
    CBLDocument *saved = [database saveDocument:newTask error:&error];
    // </doc>
    
    NSLog(@"%@", saved);
}

- (void) dontTestMutability {
    NSError *error;
    CBLMutableDocument *newTask = [[CBLMutableDocument alloc] init];
    CBLDatabase *database = self.db;
    
    // <doc>
    // newTask is a MutableDocument
    [newTask setString:@"apples" forKey:@"name"];
    [database saveDocument:newTask error:&error];
    // </doc>
}

- (void) dontTestTypedAcessors {
    CBLMutableDocument *newTask = [[CBLMutableDocument alloc] init];
    
    // <doc>
    [newTask setValue:[NSDate date] forKey:@"createdAt"];
    NSDate *date = [newTask dateForKey:@"createdAt"];
    // </doc>
    
    NSLog(@"Date: %@", date);
}

- (void) dontTestBatchOperations {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    [database inBatch:&error usingBlock:^{
        for (int i = 0; i < 10; i++) {
            CBLMutableDocument *doc = [[CBLMutableDocument alloc] init];
            [doc setValue:@"user" forKey:@"type"];
            [doc setValue:[NSString stringWithFormat:@"user %d", i] forKey:@"name"];
            [doc setBoolean:NO forKey:@"admin"];
            [database saveDocument:doc error:nil];
        }
    }];
    // </doc>
}

- (void) dontTestBlob {
#if TARGET_OS_IPHONE
    NSError *error;
    CBLDatabase *database = self.db;
    CBLMutableDocument *newTask = [[CBLMutableDocument alloc] init];
    
    // <doc>
    UIImage *appleImage = [UIImage imageNamed:@"avatar.jpg"];
    NSData *imageData = UIImageJPEGRepresentation(appleImage, 1.0);
    
    CBLBlob *blob = [[CBLBlob alloc] initWithContentType:@"image/jpeg" data:imageData];
    [newTask setBlob:blob forKey:@"avatar"];
    CBLDocument *savedDoc = [database saveDocument:newTask error:&error];
    
    CBLBlob *taskBlob = [savedDoc blobForKey:@"avatar"];
    UIImage *taskImage = [UIImage imageWithData:taskBlob.content];
    // </doc>
    
    NSLog(@"%@", taskImage);
#endif
}

#pragma mark - Query

- (void) dontTestIndexing {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLValueIndexItem *type = [CBLValueIndexItem property:@"type"];
    CBLValueIndexItem *name = [CBLValueIndexItem property:@"name"];
    CBLIndex* index = [CBLIndexBuilder valueIndexWithItems:@[type, name]];
    [database createIndex:index withName:@"TypeNameIndex" error:&error];
    // </doc>
}

- (void) dontTestSelect {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *name = [CBLQuerySelectResult property:@"name"];
    CBLQuery *query = [CBLQueryBuilder select:@[name]
                                         from:[CBLQueryDataSource database:database]
                                        where:[[[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression value:@"user"]] andExpression:
                                               [[CBLQueryExpression property:@"admin"] equalTo:[CBLQueryExpression boolean:NO]]]];
    
    NSEnumerator* rs = [query execute:&error];
    for (CBLQueryResult *result in rs) {
        NSLog(@"user name :: %@", [result stringAtIndex:0]);
    }
    // </doc>
}

- (void) dontTestSelectAll {
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuery *query = [CBLQueryBuilder select:@[[CBLQuerySelectResult all]]
                                         from:[CBLQueryDataSource database:database]];
    // </doc>
    
    NSLog(@"%@", query);
}

- (void) dontTestWhere {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuery *query = [CBLQueryBuilder select:@[[CBLQuerySelectResult all]]
                                         from:[CBLQueryDataSource database:database]
                                        where:[[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression string:@"hotel"]]
                                      groupBy:nil having:nil orderBy:nil
                                        limit:[CBLQueryLimit limit:[CBLQueryExpression integer:10]]];
    
    NSEnumerator* rs = [query execute:&error];
    for (CBLQueryResult *result in rs) {
        CBLDictionary *dict = [result valueForKey:@"travel-sample"];
        NSLog(@"document name :: %@", [dict stringForKey:@"name"]);
    }
    // </doc>
    
    NSLog(@"%@", query);
}

- (void) dontTestCollectionOperator {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *id = [CBLQuerySelectResult expression:[CBLQueryMeta id]];
    CBLQuerySelectResult *name = [CBLQuerySelectResult property:@"name"];
    CBLQuerySelectResult *likes = [CBLQuerySelectResult property:@"public_likes"];
    
    CBLQueryExpression *type = [[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression value:@"hotel"]];
    CBLQueryExpression *contains = [CBLQueryArrayFunction contains:[CBLQueryExpression property:@"public_likes"]
                                                             value:[CBLQueryExpression string:@"Armani Langworth"]];
    
    CBLQuery *query = [CBLQueryBuilder select:@[id, name, likes]
                                         from:[CBLQueryDataSource database:database]
                                        where:[type andExpression: contains]];
    
    NSEnumerator* rs = [query execute:&error];
    for (CBLQueryResult *result in rs) {
        NSLog(@"public_likes :: %@", [[result arrayForKey:@"public_likes"] toArray]);
    }
    // </doc>
}

- (void) dontTestLikeOperator {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *id = [CBLQuerySelectResult expression:[CBLQueryMeta id]];
    CBLQuerySelectResult *country = [CBLQuerySelectResult property:@"country"];
    CBLQuerySelectResult *name = [CBLQuerySelectResult property:@"name"];
    
    CBLQueryExpression *type = [[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression value:@"landmark"]];
    CBLQueryExpression *like = [[CBLQueryExpression property:@"name"] like:[CBLQueryExpression value:@"Royal engineers museum"]];
    
    CBLQuery *query = [CBLQueryBuilder select:@[id, country, name]
                                         from:[CBLQueryDataSource database:database]
                                        where:[type andExpression: like]];
    
    NSEnumerator* rs = [query execute:&error];
    for (CBLQueryResult *result in rs) {
        NSLog(@"name property :: %@", [result stringForKey:@"name"]);
    }
    // </doc>
}

- (void) dontTestWildCardMatch {
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *id = [CBLQuerySelectResult expression:[CBLQueryMeta id]];
    CBLQuerySelectResult *country = [CBLQuerySelectResult property:@"country"];
    CBLQuerySelectResult *name = [CBLQuerySelectResult property:@"name"];
    
    CBLQueryExpression *type = [[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression value:@"landmark"]];
    CBLQueryExpression *like = [[CBLQueryExpression property:@"name"] like:[CBLQueryExpression value:@"eng%e%"]];
    
    CBLQueryLimit *limit = [CBLQueryLimit limit:[CBLQueryExpression integer:10]];
    
    CBLQuery *query = [CBLQueryBuilder select:@[id, country, name]
                                         from:[CBLQueryDataSource database:database]
                                        where:[type andExpression: like]
                                      groupBy:nil having:nil orderBy:nil
                                        limit:limit];
    // </doc>
    
    NSLog(@"%@", query);
}

- (void) dontTestWildCardCharacterMatch {
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *id = [CBLQuerySelectResult expression:[CBLQueryMeta id]];
    CBLQuerySelectResult *country = [CBLQuerySelectResult property:@"country"];
    CBLQuerySelectResult *name = [CBLQuerySelectResult property:@"name"];
    
    CBLQueryExpression *type = [[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression value:@"landmark"]];
    CBLQueryExpression *like = [[CBLQueryExpression property:@"name"] like:[CBLQueryExpression value:@"eng____r"]];
    
    CBLQueryLimit *limit = [CBLQueryLimit limit:[CBLQueryExpression integer:10]];
    
    CBLQuery *query = [CBLQueryBuilder select:@[id, country, name]
                                         from:[CBLQueryDataSource database:database]
                                        where:[type andExpression: like]
                                      groupBy:nil having:nil orderBy:nil
                                        limit:limit];
    // </doc>
    
    NSLog(@"%@", query);
}

- (void) dontTestRegexMatch {
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *id = [CBLQuerySelectResult expression:[CBLQueryMeta id]];
    CBLQuerySelectResult *name = [CBLQuerySelectResult property:@"name"];
    
    CBLQueryExpression *type = [[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression value:@"landmark"]];
    CBLQueryExpression *regex = [[CBLQueryExpression property:@"name"] regex:[CBLQueryExpression value:@"\\bEng.*e\\b"]];
    
    CBLQueryLimit *limit = [CBLQueryLimit limit:[CBLQueryExpression integer:10]];
    
    CBLQuery *query = [CBLQueryBuilder select:@[id, name]
                                         from:[CBLQueryDataSource database:database]
                                        where:[type andExpression: regex]
                                      groupBy:nil having:nil orderBy:nil
                                        limit:limit];
    // </doc>
    
    NSLog(@"%@", query);
}

- (void) dontTestJoin {
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *name = [CBLQuerySelectResult expression:[CBLQueryExpression property:@"name" from:@"airline"]];
    CBLQuerySelectResult *callsign = [CBLQuerySelectResult expression:[CBLQueryExpression property:@"callsign" from:@"airline"]];
    CBLQuerySelectResult *dest = [CBLQuerySelectResult expression:[CBLQueryExpression property:@"destinationairport" from:@"route"]];
    CBLQuerySelectResult *stops = [CBLQuerySelectResult expression:[CBLQueryExpression property:@"stops" from:@"route"]];
    CBLQuerySelectResult *airline = [CBLQuerySelectResult expression:[CBLQueryExpression property:@"airline" from:@"route"]];
    
    CBLQueryJoin *join = [CBLQueryJoin join:[CBLQueryDataSource database:database as:@"route"]
                                         on:[[CBLQueryMeta idFrom:@"airline"] equalTo:[CBLQueryExpression property:@"airlineid" from:@"route"]]];
    
    CBLQueryExpression *typeRoute = [[CBLQueryExpression property:@"type" from:@"route"] equalTo:[CBLQueryExpression value:@"route"]];
    CBLQueryExpression *typeAirline = [[CBLQueryExpression property:@"type" from:@"airline"] equalTo:[CBLQueryExpression value:@"airline"]];
    CBLQueryExpression *sourceRIX = [[CBLQueryExpression property:@"sourceairport" from:@"route"] equalTo:[CBLQueryExpression value:@"RIX"]];
    
    CBLQuery *query = [CBLQueryBuilder select:@[name, callsign, dest, stops, airline]
                                         from:[CBLQueryDataSource database:database as:@"airline"]
                                         join:@[join]
                                        where:[[typeRoute andExpression:typeAirline] andExpression:sourceRIX]];
    // </doc>
    
    NSLog(@"%@", query);
}

- (void) dontTestGroupBy {
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *count = [CBLQuerySelectResult expression:[CBLQueryFunction count:[CBLQueryExpression all]]];
    CBLQuerySelectResult *country = [CBLQuerySelectResult property:@"country"];
    CBLQuerySelectResult *tz = [CBLQuerySelectResult property:@"tz"];
    
    CBLQueryExpression *type = [[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression value:@"airport"]];
    CBLQueryExpression *geoAlt = [[CBLQueryExpression property:@"geo.alt"] greaterThanOrEqualTo:[CBLQueryExpression integer:300]];
    
    CBLQuery *query = [CBLQueryBuilder select:@[count, country, tz]
                                         from:[CBLQueryDataSource database:database]
                                        where:[type andExpression: geoAlt]
                                      groupBy:@[[CBLQueryExpression property:@"country"],
                                                [CBLQueryExpression property:@"tz"]]];
    // </doc>
    
    NSLog(@"%@", query);
}

- (void) dontTestOrderBy {
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQuerySelectResult *id = [CBLQuerySelectResult expression:[CBLQueryMeta id]];
    CBLQuerySelectResult *title = [CBLQuerySelectResult property:@"title"];
    
    CBLQuery *query = [CBLQueryBuilder select:@[id, title]
                                         from:[CBLQueryDataSource database:database]
                                        where:[[CBLQueryExpression property:@"type"] equalTo:[CBLQueryExpression value:@"hotel"]]
                                      orderBy:@[[[CBLQueryOrdering property:@"title"] descending]]];
    // </doc>
    
    NSLog(@"%@", query);
}

- (void) dontTestCreateFullTextIndex {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    // Insert documents
    NSArray *tasks = @[@"buy groceries", @"play chess", @"book travels", @"buy museum tickets"];
    for (NSString *task in tasks) {
        CBLMutableDocument *doc = [[CBLMutableDocument alloc] init];
        [doc setString:@"task" forKey:@"type"];
        [doc setString:task forKey:@"name"];
        [database saveDocument:doc error:&error];
    }
    
    // Create index
    CBLFullTextIndex *index = [CBLIndexBuilder fullTextIndexWithItems:@[[CBLFullTextIndexItem property:@"name"]]];
    index.ignoreAccents = NO;
    [database createIndex:index withName:@"nameFTSIndex" error:&error];
    // </doc>
}

- (void) dontTestFullTextSearch {
    NSError *error;
    CBLDatabase *database = self.db;
    
    // <doc>
    CBLQueryExpression *where = [[CBLQueryFullTextExpression indexWithName:@"nameFTSIndex"] match:@"'buy'"];
    CBLQuery *query = [CBLQueryBuilder select:@[[CBLQuerySelectResult expression:[CBLQueryMeta id]]]
                                         from:[CBLQueryDataSource database:database]
                                        where:where];
    
    NSEnumerator* rs = [query execute:&error];
    for (CBLQueryResult *result in rs) {
        NSLog(@"document id %@", [result stringAtIndex:0]);
    }
    // </doc>
}

#pragma mark - Replication

- (void) dontTestStartReplication {
    CBLDatabase *database = self.db;
    
    // <doc>
    NSURL *url = [NSURL URLWithString:@"ws://localhost:4984/db"];
    CBLURLEndpoint *target = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration *config = [[CBLReplicatorConfiguration alloc] initWithDatabase:database
                                                                                       target:target];
    config.replicatorType = kCBLReplicatorTypePull;
    CBLReplicator *replicator = [[CBLReplicator alloc] initWithConfig:config];
    [replicator start];
    // </doc>
}

- (void) dontTestEnableReplicatorLogging {
    // <doc>
    // Replicator
    [CBLDatabase setLogLevel:kCBLLogLevelVerbose domain:kCBLLogDomainReplicator];
    // Network
    [CBLDatabase setLogLevel:kCBLLogLevelVerbose domain:kCBLLogDomainNetwork];
    // </doc>
}

- (void) dontTestReplicatorStatus {
    CBLDatabase *database = self.db;
    NSURL *url = [NSURL URLWithString:@"ws://localhost:4984/db"];
    CBLURLEndpoint *target = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration *config = [[CBLReplicatorConfiguration alloc] initWithDatabase:database target:target];
    CBLReplicator *replicator = [[CBLReplicator alloc] initWithConfig:config];
    
    // <doc>
    [replicator addChangeListener:^(CBLReplicatorChange *change) {
        if (change.status.activity == kCBLReplicatorStopped) {
            NSLog(@"Replication stopped");
        }
    }];
    // </doc>
}

- (void) dontTestHandlingReplicationError {
    CBLDatabase *database = self.db;
    NSURL *url = [NSURL URLWithString:@"ws://localhost:4984/db"];
    CBLURLEndpoint *target = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration *config = [[CBLReplicatorConfiguration alloc] initWithDatabase:database target:target];
    CBLReplicator *replicator = [[CBLReplicator alloc] initWithConfig:config];
    
    // <doc>
    [replicator addChangeListener:^(CBLReplicatorChange *change) {
        if (change.status.error) {
            NSLog(@"Error code: %ld", change.status.error.code);
        }
    }];
    // </doc>
}

- (void) dontTestCertificatePinning {
    CBLDatabase *database = self.db;
    NSURL *url = [NSURL URLWithString:@"ws://localhost:4984/db"];
    CBLURLEndpoint *target = [[CBLURLEndpoint alloc] initWithURL: url];
    
    // <doc>
    NSData *data = [self dataFromResource: @"cert" ofType: @"cer"];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
    CBLReplicatorConfiguration *config = [[CBLReplicatorConfiguration alloc] initWithDatabase:database
                                                                                       target:target];
    config.pinnedServerCertificate = (SecCertificateRef)CFAutorelease(cert);
    // </doc>
    
    NSLog(@"%@", config);
}

@end


// Singleton Pattern
// <doc>
@interface DataManager : NSObject

@property (nonatomic, readonly) CBLDatabase *database;

+ (id)sharedInstance;

@end

@implementation DataManager

@synthesize database=_database;

+ (id)sharedInstance {
    static DataManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    if (self = [super init]) {
        NSError *error;
        _database = [[CBLDatabase alloc] initWithName:@"dbname" error:&error];
        if (!_database) {
            NSLog(@"Cannot open the database: %@", error);
            return nil;
        }
    }
    return self;
}

@end
// <doc>
