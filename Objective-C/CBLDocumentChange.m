//
//  CBLDocumentChange.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDocumentChange.h"
#import "CBLDatabase+Internal.h"

@implementation CBLDocumentChange

@synthesize database=_database, documentID=_documentID;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString *)documentID
{
    self = [super init];
    if (self) {
        _database = database;
        _documentID = documentID;
    }
    return self;
}

@end
