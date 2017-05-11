//
//  ConflictTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/26/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLInternal.h"

#include "c4.h"
#include "c4Document+Fleece.h"
#include "Fleece.h"
#include "Fleece+CoreFoundation.h"

@interface TheirsWins : NSObject <CBLConflictResolver>
@end

@implementation TheirsWins

- (CBLReadOnlyDocument*) resolve: (CBLConflict *)conflict {
    return conflict.target;
}

@end


@interface MergeThenTheirsWins : NSObject <CBLConflictResolver>
@end

@implementation MergeThenTheirsWins

- (CBLReadOnlyDocument*) resolve: (CBLConflict *)conflict {
    CBLDocument* resolved = [[CBLDocument alloc] init];
    for (NSString* key in [conflict.commonAncestor allKeys]) {
        [resolved setObject: [conflict.commonAncestor objectForKey: key] forKey: key];
    }
    
    NSMutableSet *changed = [NSMutableSet new];
    for (NSString* key in [conflict.target allKeys]) {
        [resolved setObject: [conflict.target objectForKey: key] forKey: key];
        [changed addObject: key];
    }
    
    for (NSString* key in [conflict.source allKeys]) {
        if(![changed containsObject: key]) {
            [resolved setObject: [conflict.source objectForKey: key] forKey: key];
        }
    }
    return resolved;
}

@end


@interface GiveUp : NSObject <CBLConflictResolver>
@end

@implementation GiveUp

- (CBLReadOnlyDocument*) resolve: (CBLConflict *)conflict {
    return nil;
}

@end


@interface DoNotResolve : NSObject <CBLConflictResolver>
@end

@implementation DoNotResolve

- (CBLReadOnlyDocument*) resolve: (CBLConflict*)conflict {
    NSAssert(NO, @"Resolver should not have been called!");
    return nil;
}

@end


@interface ConflictTest : CBLTestCase

@end

@implementation ConflictTest


- (void) setUp {
    [super setUp];
    
    // Make sure resolver isn't being called at inappropriate times by defaulting to one that
    // will raise an exception:
    @autoreleasepool {
        self.db.conflictResolver = [DoNotResolve new];
    }
}


- (void) reopenDB {
    [super reopenDB];
    self.db.conflictResolver = [DoNotResolve new];
}


- (CBLDocument*) setupConflict {
    // Setup a default database conflict resolver
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: @"profile" forKey: @"type"];
    [doc setObject: @"Scott" forKey: @"name"];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    // Force a conflict
    NSMutableDictionary *properties = [[doc toDictionary] mutableCopy];
    properties[@"name"] = @"Scotty";
    BOOL ok = [self saveProperties: properties toDocWithID: [doc documentID] error: &error];
    Assert(ok);
    
    // Change document in memory, so save will trigger a conflict
    [doc setObject: @"Scott Pilgrim" forKey: @"name"];
    
    return doc;
}


- (BOOL)saveProperties: (NSDictionary*)props toDocWithID: (NSString*)docID error: (NSError**)error {
    // Save to database:
    BOOL ok = [self.db inBatch: error do: ^{
        C4Slice docIDSlice = c4str([docID cStringUsingEncoding: NSASCIIStringEncoding]);
        C4Document* tricky = c4doc_get(self.db.c4db, docIDSlice, true, NULL);
        
        C4DocPutRequest put = {
            .docID = tricky->docID,
            .history = &tricky->revID,
            .historyCount = 1,
            .save = true,
        };
        
        NSMutableDictionary* properties = [props mutableCopy];
        FLEncoder enc = c4db_createFleeceEncoder(self.db.c4db);
        FLEncoder_WriteNSObject(enc, properties);
        FLError flErr;
        FLSliceResult body = FLEncoder_Finish(enc, &flErr);
        FLEncoder_Free(enc);
        Assert(body.buf);
        put.body = (C4Slice){body.buf, body.size};
        
        C4Error err;
        C4Document* newDoc = c4doc_put(self.db.c4db, &put, NULL, &err);
        c4slice_free(put.body);
        Assert(newDoc, @"Couldn't save c4doc: %d/%d", err.domain, err.code);
        c4doc_free(newDoc);
        c4doc_free(tricky);
    }];
    
    Assert(ok);
    return YES;
}


- (void)testConflict {
    NSError* error;
    self.db.conflictResolver = [TheirsWins new];
    CBLDocument* doc1 = [self setupConflict];
    Assert([_db saveDocument: doc1 error: &error], @"Saving error: %@", error);
    AssertEqualObjects([doc1 objectForKey: @"name"], @"Scotty");
    
    // Get a new document with its own conflict resolver
    CBLDocument* doc2 = [[CBLDocument alloc] initWithID: @"doc2"];
    
    self.db.conflictResolver = [MergeThenTheirsWins new];
    [doc2 setObject: @"profile" forKey: @"type"];
    [doc2 setObject: @"Scott" forKey: @"name"];
    
    Assert([_db saveDocument: doc2 error: &error], @"Saving error: %@", error);
    
    // Force a conflict again
    NSMutableDictionary* properties = [[doc2 toDictionary] mutableCopy];
    properties[@"type"] = @"bio";
    properties[@"gender"] = @"male";
    BOOL ok = [self saveProperties: properties toDocWithID: doc2.documentID error: &error];
    Assert(ok);
    
    // Save and make sure that the correct conflict resolver won
    [doc2 setObject:@"biography" forKey: @"type"];
    [doc2 setObject: @(31) forKey: @"age"];
    
    Assert([_db saveDocument: doc2 error: &error], @"Saving error: %@", error);
    
    AssertEqual([doc2 integerForKey: @"age"], 31);
    AssertEqualObjects([doc2 stringForKey: @"type"], @"bio");
    AssertEqualObjects([doc2 stringForKey: @"gender"], @"male");
    AssertEqualObjects([doc2 stringForKey: @"name"], @"Scott");
}


- (void)testConflictResolverGivesUp {
    self.db.conflictResolver = [GiveUp new];
    CBLDocument* doc = [self setupConflict];
    NSError* error;
    AssertFalse([_db saveDocument: doc error: &error], @"Save should have failed!");
    AssertEqualObjects(error.domain, @"LiteCore");      //TODO: Should have CBL error domain/code
    AssertEqual(error.code, kC4ErrorConflict);
}


- (void)testDeletionConflict {
    self.db.conflictResolver = [DoNotResolve new];
    CBLDocument* doc = [self setupConflict];
    NSError* error;
    Assert([_db deleteDocument: doc error: &error], @"Deletion error: %@", error);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc stringForKey: @"name"], @"Scotty");
}


- (void)testConflictMineIsDeeper {
    self.db.conflictResolver = nil;
    CBLDocument* doc = [self setupConflict];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertEqualObjects([doc stringForKey: @"name"], @"Scott Pilgrim");
}


- (void)testConflictTheirsIsDeeper {
    self.db.conflictResolver = nil;
    CBLDocument* doc = [self setupConflict];
    
    // Add another revision to the conflict, so it'll have a higher generation:
    NSMutableDictionary *properties = [[doc toDictionary] mutableCopy];
    properties[@"name"] = @"Scott of the Sahara";
    NSError* error;
    [self saveProperties:properties toDocWithID:[doc documentID] error:&error];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertEqualObjects([doc stringForKey: @"name"], @"Scott of the Sahara");
}


@end
