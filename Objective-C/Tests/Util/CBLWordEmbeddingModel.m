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

- (instancetype) initWithDatabase: (CBLDatabase*)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (CBLArray*) vectorForWord: (NSString*)word collection: (NSString*)collection {
    NSError* error;
    NSString* sql = [NSString stringWithFormat: @"select vector from %@ where word = '%@'", collection, word];
    CBLQuery* q = [_database createQuery: sql error: &error];
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray<CBLQueryResult*>* results = [rs allResults];
    
    if (results.count == 0) {
        return nil;
    }
    
    CBLQueryResult* result = results[0];
    return [result arrayForKey: @"vector"];
}


- (CBLDictionary*) predict: (CBLDictionary*)input {
    NSString* inputWord = [input stringForKey: @"word"];
    
    assert(inputWord);
    
    CBLArray* result = [self vectorForWord: inputWord collection: @"words"];
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


