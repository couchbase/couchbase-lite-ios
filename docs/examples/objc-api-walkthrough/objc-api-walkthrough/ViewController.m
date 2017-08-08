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
//    NSError* error;
    CBLDocument* newTask = [[CBLDocument alloc] init];
    [newTask setObject:@"task-list" forKey:@"type"];
    [newTask setObject:@"todo" forKey:@"owner"];
    [newTask setObject:[NSDate date] forKey:@"createAt"];
    [database saveDocument: newTask error: &error];
    
    // mutate document
    [newTask setObject:@"Apples" forKey:@"name"];
    [database saveDocument:newTask error:&error];
    
    // typed accessors
    [newTask setObject:[NSDate date] forKey:@"createdAt"];
    NSDate* date = [newTask dateForKey:@"createdAt"];
    
    // database batch operation
    [database inBatch:&error do:^{
        for (int i = 1; i <= 10; i++)
        {
            NSError* error;
            CBLDocument *doc = [[CBLDocument alloc] init];
            [doc setObject:@"user" forKey:@"type"];
            [doc setObject:[NSString stringWithFormat:@"user %d", i] forKey:@"name"];
            [database saveDocument:doc error:&error];
            NSLog(@"saved user document %@", [doc stringForKey:@"name"]);
        }
    }];
    
    // blob
    UIImage *image = [UIImage imageNamed:@"avatar.jpg"];
    NSData *data = UIImageJPEGRepresentation(image, 1);
    
    CBLBlob *blob = [[CBLBlob alloc] initWithContentType:@"image/jpg" data:data];
    [newTask setObject:blob forKey: @"avatar"];
    
//    NSError* error;
    [database saveDocument: newTask error:&error];
    if (error) {
        NSLog(@"Cannot save document %@", error);
    }
    
    CBLBlob* taskBlob = [newTask blobForKey:@"avatar"];
    UIImage* taskImage = [UIImage imageWithData:taskBlob.content];
    
    // query
    CBLQuery* query = [CBLQuery select:@[]
                                  from:[CBLQueryDataSource database:database]
                                 where:[
                                        [[CBLQueryExpression property:@"type"] equalTo:@"user"]
                                        and: [[CBLQueryExpression property:@"admin"] equalTo:@FALSE]]];
    
    NSEnumerator* rows = [query run:&error];
    for (CBLQueryRow *row in rows) {
        NSLog(@"doc ID :: %@", row.documentID);
    }
    
    // fts example
    // insert documents
    NSArray *tasks = @[@"buy groceries", @"play chess", @"book travels", @"buy museum tickets"];
    for (NSString* task in tasks) {
        CBLDocument* doc = [[CBLDocument alloc] init];
        [doc setObject: @"task" forKey: @"type"];
        [doc setObject: task forKey: @"name"];
        
        NSError* error;
        [database saveDocument: newTask error:&error];
        if (error) {
            NSLog(@"Cannot save document %@", error);
        }
    }
    
    // create index
    [database createIndexOn:@[@"name"] type:kCBLFullTextIndex options:NULL error:&error];
    if (error) {
        NSLog(@"Cannot create index %@", error);
    }
    
    CBLQueryExpression* where = [[CBLQueryExpression property:@"name"] match:@"'buy'"];
    CBLQuery *ftsQuery = [CBLQuery select:@[]
                                     from:[CBLQueryDataSource database:database]
                                    where:where];
    
    NSEnumerator* ftsQueryResult = [ftsQuery run:&error];
    for (CBLFullTextQueryRow *row in ftsQueryResult) {
        NSLog(@"document properties :: %@", [row.document toDictionary]);
    }
    
    // create conflict
    /*
     * 1. Create a document twice with the same ID.
     * 2. The `theirs` properties in the conflict resolver represents the current rev and
     * `mine` is what's being saved.
     * 3. Read the document after the second save operation and verify its property is as expected.
     */
    CBLDocument* theirs = [[CBLDocument alloc] initWithID:@"buzz"];
    [theirs setObject:@"theirs" forKey:@"status"];
    CBLDocument* mine = [[CBLDocument alloc] initWithID:@"buzz"];
    [mine setObject:@"mine" forKey:@"status"];
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
        if (change.status.activity == kCBLStopped) {
            NSLog(@"Replication was completed.");
        }
    }];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
