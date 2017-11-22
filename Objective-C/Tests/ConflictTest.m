//
//  ConflictTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/26/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "ConflictTest.h"
#import "CBLDatabase+Internal.h"

#include "c4.h"
#include "c4Document+Fleece.h"
#include "Fleece.h"
#include "Fleece+CoreFoundation.h"


@implementation DoNotResolve

- (CBLDocument*) resolve: (CBLConflict*)conflict {
    NSAssert(NO, @"Resolver should not have been called!");
    return nil;
}

@end


@implementation TheirsWins

- (CBLDocument*) resolve: (CBLConflict *)conflict {
    return conflict.theirs;
}

@end


@implementation MergeThenTheirsWins

@synthesize requireBaseRevision=_requireBaseRevision;

- (CBLDocument*) resolve: (CBLConflict *)conflict {
    if (_requireBaseRevision)
        NSAssert(conflict.base != nil, @"Missing base");
    CBLMutableDocument* resolved = [[CBLMutableDocument alloc] init];
    for (NSString* key in conflict.base) {
        [resolved setValue: [conflict.base valueForKey: key] forKey: key];
    }
    
    NSMutableSet *changed = [NSMutableSet new];
    for (NSString* key in conflict.theirs) {
        [resolved setValue: [conflict.theirs valueForKey: key] forKey: key];
        [changed addObject: key];
    }
    
    for (NSString* key in conflict.mine) {
        if(![changed containsObject: key]) {
            [resolved setValue: [conflict.mine valueForKey: key] forKey: key];
        }
    }
    return resolved;
}

@end


@implementation GiveUp

- (CBLDocument*) resolve: (CBLConflict *)conflict {
    return nil;
}

@end


@implementation BlockResolver

@synthesize block=_block;

- (instancetype) initWithBlock: (nullable CBLDocument* (^)(CBLConflict*))block {
    self = [super init];
    if (self) {
        _block = block;
    }
    return self;
}

- (CBLDocument*) resolve: (CBLConflict *)conflict {
    return self.block(conflict);
}

@end

@interface ConflictTest : CBLTestCase

@end

@implementation ConflictTest


- (void) setUp {
    self.conflictResolver = [DoNotResolve new];
    [super setUp];
}


- (CBLMutableDocument*) setupConflict {
    // Setup a default database conflict resolver
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc setValue: @"profile" forKey: @"type"];
    [doc setValue: @"Scott" forKey: @"name"];
    NSError* error;
    CBLDocument* savedDoc = [_db saveDocument: doc error: &error];
    Assert(savedDoc, @"Saving error: %@", error);
    
    // Force a conflict
    NSMutableDictionary *properties = [[doc toDictionary] mutableCopy];
    properties[@"name"] = @"Scotty";
    BOOL ok = [self saveProperties: properties toDocWithID: doc.id error: &error];
    Assert(ok);
    
    // Change document in memory, so save will trigger a conflict
    doc = [savedDoc toMutable];
    [doc setValue: @"Scott Pilgrim" forKey: @"name"];
    
    return doc;
}


- (BOOL) saveProperties: (NSDictionary*)props
            toDocWithID: (NSString*)docID
                  error: (NSError**)error
{
    // Save to database:
    BOOL ok = [self.db inBatch: error usingBlock: ^{
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


- (void) testConflict {
    NSError* error;
    self.conflictResolver = [TheirsWins new];
    [self reopenDB];
    
    CBLMutableDocument* doc1 = [self setupConflict];
    CBLDocument* savedDoc1 = [_db saveDocument: doc1 error: &error];
    Assert(savedDoc1, @"Saving error: %@", error);
    AssertEqualObjects([savedDoc1 valueForKey: @"name"], @"Scotty");
    
    // Get a new document with its own conflict resolver
    self.conflictResolver = [MergeThenTheirsWins new];
    [self reopenDB];
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"profile" forKey: @"type"];
    [doc2 setValue: @"Scott" forKey: @"name"];
    CBLDocument* savedDoc2 = [_db saveDocument: doc2 error: &error];
    Assert(savedDoc2, @"Saving error: %@", error);
    
    // Force a conflict again
    NSMutableDictionary* properties = [[doc2 toDictionary] mutableCopy];
    properties[@"type"] = @"bio";
    properties[@"gender"] = @"male";
    BOOL ok = [self saveProperties: properties toDocWithID: doc2.id error: &error];
    Assert(ok);
    
    // Save and make sure that the correct conflict resolver won
    doc2 = [savedDoc2 toMutable];
    [doc2 setValue: @"biography" forKey: @"type"];
    [doc2 setValue: @(31) forKey: @"age"];
    
    savedDoc2 = [_db saveDocument: doc2 error: &error];
    Assert(savedDoc2, @"Saving error: %@", error);
    
    AssertEqual([savedDoc2 integerForKey: @"age"], 31);
    AssertEqualObjects([savedDoc2 stringForKey: @"type"], @"bio");
    AssertEqualObjects([savedDoc2 stringForKey: @"gender"], @"male");
    AssertEqualObjects([savedDoc2 stringForKey: @"name"], @"Scott");
}


- (void) testConflictResolverGivesUp {
    self.conflictResolver = [GiveUp new];
    [self reopenDB];
    
    CBLMutableDocument* doc = [self setupConflict];
    NSError* error;
    AssertFalse([_db saveDocument: doc error: &error], @"Save should have failed!");
    AssertEqualObjects(error.domain, @"LiteCore");      //TODO: Should have CBL error domain/code
    AssertEqual(error.code, kC4ErrorConflict);
}


- (void) testConflictDeletion {
    self.conflictResolver = nil;
    [self reopenDB];
    
    CBLMutableDocument* doc = [self setupConflict];
    NSError* error;
    Assert([_db deleteDocument: doc
                         error: &error], @"Deletion error: %@", error);
    
    CBLDocument* savedDoc = [_db documentWithID: doc.id];
    AssertNil(savedDoc);
}


- (void) testConflictMineIsDeeper {
    self.conflictResolver = nil;
    [self reopenDB];
    
    CBLMutableDocument* doc = [self setupConflict];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertEqualObjects([doc stringForKey: @"name"], @"Scott Pilgrim");
}


- (void) testConflictTheirsIsDeeper {
    self.conflictResolver = nil;
    [self reopenDB];
    
    CBLMutableDocument* doc = [self setupConflict];
    
    // Add another revision to the conflict, so it'll have a higher generation:
    NSMutableDictionary *properties = [[doc toDictionary] mutableCopy];
    properties[@"name"] = @"Scott of the Sahara";
    NSError* error;
    [self saveProperties:properties toDocWithID: doc.id error:&error];
    
    CBLDocument* savedDoc = [_db saveDocument: doc error: &error];
    Assert(savedDoc, @"Saving error: %@", error);
    AssertEqualObjects([savedDoc stringForKey: @"name"], @"Scott of the Sahara");
}


- (void) testNoBase {
    self.conflictResolver = [[BlockResolver alloc] initWithBlock:
                             ^CBLDocument* (CBLConflict* conflict)
    {
        AssertEqualObjects([conflict.mine valueForKey: @"name"], @"Tiger");
        AssertEqualObjects([conflict.theirs valueForKey: @"name"], @"Daniel");
        AssertNil(conflict.base);
        return conflict.mine;
    }];
    [self reopenDB];
    
    CBLMutableDocument* doc1a = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1a setValue: @"Daniel" forKey: @"name"];
    [self saveDocument: doc1a];
    
    CBLMutableDocument* doc1b = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1b setValue: @"Tiger" forKey: @"name"];
    [self saveDocument: doc1b];
    
    AssertEqualObjects([doc1b valueForKey:@"name"], @"Tiger");
}


@end
