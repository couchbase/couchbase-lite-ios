//
//  ViewController.m
//  objc-api-walkthrough
//
//  Created by James Nocentini on 27/06/2017.
//  Copyright © 2017 couchbase. All rights reserved.
//

#import "ViewController.h"
#include <CouchbaseLite/CouchbaseLite.h>
#import "ExampleConflictResolver.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // create database
    NSError *error;
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    [config setConflictResolver:[[ExampleConflictResolver alloc] init]];
    CBLDatabase* database = [[CBLDatabase alloc] initWithName:@"my-database" config:config error:&error];
    if (!database) {
        NSLog(@"Cannot open the database: %@", error);
    }
    
    // create document
    CBLMutableDocument* newTask = [[CBLMutableDocument alloc] init];
    [newTask setValue:@"task-list" forKey:@"type"];
    [newTask setValue:@"todo" forKey:@"owner"];
    [newTask setValue:[NSDate date] forKey:@"createAt"];
    [database saveDocument: newTask error: &error];
    
    // mutate document
    [newTask setValue:@"Apples" forKey:@"name"];
    [database saveDocument:newTask error:&error];
    
    // typed accessors
    [newTask setValue:[NSDate date] forKey:@"createdAt"];
    NSDate* date = [newTask dateForKey:@"createdAt"];
    
    // database batch operation
    [database inBatch:&error usingBlock:^{
        for (int i = 1; i <= 10; i++) {
            NSError* error;
            CBLMutableDocument *doc = [[CBLMutableDocument alloc] init];
            [doc setValue:@"user" forKey:@"type"];
            [doc setValue:[NSString stringWithFormat:@"user %d", i] forKey:@"name"];
            [doc setBoolean:@FALSE forKey:@"admin"];
            [database saveDocument:doc error:&error];
            NSLog(@"saved user document %@", [doc stringForKey:@"name"]);
        }
    }];
    
    // blob
    UIImage *image = [UIImage imageNamed:@"avatar.jpg"];
    NSData *data = UIImageJPEGRepresentation(image, 1);
    
    CBLBlob *blob = [[CBLBlob alloc] initWithContentType:@"image/jpg" data:data];
    [newTask setValue:blob forKey: @"avatar"];
    
    [database saveDocument: newTask error:&error];
    if (error) {
        NSLog(@"Cannot save document %@", error);
    }
    
    CBLBlob* taskBlob = [newTask blobForKey:@"avatar"];
    UIImage* taskImage = [UIImage imageWithData:taskBlob.content];
    
    // query
    CBLQuery* query = [CBLQuery select:@[[CBLQueryExpression property:@"name"]]
                                  from:[CBLQueryDataSource database:database]
                                 where:[
                                        [[CBLQueryExpression property:@"type"] equalTo:@"user"]
                                        andExpression: [[CBLQueryExpression property:@"admin"] equalTo:@FALSE]]];
    
    NSEnumerator* rows = [query execute:&error];
    for (CBLQueryRow *row in rows) {
        NSLog(@"user name :: %@", [row stringAtIndex:0]);
    }
    
    // fts example
    // insert documents
    NSArray *tasks = @[@"buy groceries", @"play chess", @"book travels", @"buy museum tickets"];
    for (NSString* task in tasks) {
        CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
        [doc setValue: @"task" forKey: @"type"];
        [doc setValue: task forKey: @"name"];
        
        NSError* error;
        [database saveDocument: newTask error:&error];
        if (error) {
            NSLog(@"Cannot save document %@", error);
        }
    }
    
    // create index
    CBLIndex* index = [CBLIndex fullTextIndexWithItems : @[[CBLFullTextIndexItem property: @"name"]] options: nil];
    [database createIndex: index withName: @"name_idx" error: &error];
    if (error) {
        NSLog(@"Cannot create index %@", error);
    }
    
    CBLQueryExpression* where = [[CBLQueryFullTextExpression index:@"name_idx"] match:@"'buy'"];
    CBLQuery *ftsQuery = [CBLQuery select:@[]
                                     from:[CBLQueryDataSource database:database]
                                    where:where];
    
    NSEnumerator* results = [ftsQuery execute:&error];
    for (CBLQueryResult *row in results) {
        NSLog(@"document properties :: %@", [row toDictionary]);
    }
    
    // create conflict
    /*
     * 1. Create a document twice with the same ID.
     * 2. The `theirs` properties in the conflict resolver represents the current rev and
     * `mine` is what's being saved.
     * 3. Read the document after the second save operation and verify its property is as expected.
     */
    CBLMutableDocument* theirs = [[CBLMutableDocument alloc] initWithID:@"buzz"];
    [theirs setValue:@"theirs" forKey:@"status"];
    CBLMutableDocument* mine = [[CBLMutableDocument alloc] initWithID:@"buzz"];
    [mine setValue:@"mine" forKey:@"status"];
    [database saveDocument:theirs error:nil];
    [database saveDocument:mine error:nil];
    
    CBLDocument* conflictResolverResult = [database documentWithID:@"buzz"];
    NSLog(@"conflictResolverResult doc.status ::: %@", [conflictResolverResult stringForKey:@"status"]);
    
    // replication
    NSURL *url = [[NSURL alloc] initWithString:@"blip://localhost:4984/db"];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:database targetURL:url];
    CBLReplicator *replication = [[CBLReplicator alloc] initWithConfig: replConfig];
    [replication start];
    
    // replication change listener
    [replication addChangeListener:^(CBLReplicatorChange * _Nonnull change) {
        if (change.status.activity == kCBLReplicatorStopped) {
            NSLog(@"Replication was completed.");
        }
    }];
}

@end
