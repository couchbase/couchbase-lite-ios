//
//  CBLWordEmbeddingModel.m
//  CBL_EE_ObjC
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
//  COUCHBASE CONFIDENTIAL -- part of Couchbase Lite Enterprise Edition
//

#import "CBLWordEmbeddingModel.h"

@implementation CBLWordEmbeddingModel {
    CBLDatabase* _database;
}

- (instancetype) init: (CBLDatabase*)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (NSArray*) vectorForWord: (NSString*)word collection: (NSString*)collection {
    NSError* error;
    NSString* sql = [NSString stringWithFormat: @"select vector from %@ where word = %@", collection, word];
    CBLQuery* q = [_database createQuery: sql error: &error];
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* results = [rs allResults];
    return results.count > 0 ? results[0][@"word"] : nil;
}


- (CBLDictionary*) predict: (CBLDictionary*)input {
    NSString* inputWord = [input stringForKey: @"word"];
    
    if (!inputWord) {
        NSLog(@"No word input !!!");
        return nil;
    }
    
    NSArray* result = [self vectorForWord: inputWord collection: @"words"];
    if (!result) {
        result = [self vectorForWord: inputWord collection: @"extwords"];
    }
    
    if (!result) {
        return nil;
    }
    
    CBLMutableDictionary* output = [[CBLMutableDictionary alloc] init];
    [output setValue: result forKey: @"vector"];
    return output;
}

@end


