//
//  TDDocument.m
//  TouchDB
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDocument.h"
#import "TDDatabase+Insertion.h"
#import "TDServer.h"


@implementation TDDocument


- (id)initWithServer: (TDServer*)server
        databaseName: (NSString*)name
               docID: (NSString*)docID
           numericID: (UInt64)numericID
{
    self = [super init];
    if (self) {
        _server = server;
        _databaseName = [name copy];
        _docID = [docID copy];
        _numericID = numericID;
    }
    return self;
}


- (void)dealloc
{
    [_docID release];
    [super dealloc];
}


@synthesize database=_database, documentID=_docID, isDeleted=_deleted;


- (TDRevision*) currentRevision {
    if (!_currentRevision) {
        _currentRevisionOptions = 0;
        _currentRevision = [[self revisionWithID: nil
                                         options: _currentRevisionOptions] retain];
        _deleted = _currentRevision.deleted;
    }
    return _currentRevision;
}


- (NSString*) currentRevisionID {
    return self.currentRevision.revID;
}


- (TDRevision*) revisionWithID: (NSString*)revID {
    return [self revisionWithID: revID options: 0];
}

- (TDRevision*) revisionWithID: (NSString*)revID options: (TDContentOptions)options {
    return [_server waitForDatabaseNamed: _databaseName to: ^(TDDatabase* db) {
        return [[db getDocumentWithID: _docID revisionID: revID options: options] retain];
    }];
}


- (NSDictionary*) properties {
    return self.currentRevision.properties;
}

- (id) propertyForKey: (NSString*)key {
    return [self.currentRevision.properties objectForKey: key];
}

- (NSDictionary*) userProperties {
    NSDictionary* rep = [self properties];
    if (!rep)
        return nil;
    NSMutableDictionary* props = [NSMutableDictionary dictionary];
    for (NSString* key in rep) {
        if (![key hasPrefix: @"_"])
            [props setObject: [rep objectForKey: key] forKey: key];
    }
    return props;
}


- (TDStatus) putProperties: (NSDictionary*)properties {
    NSString* prevID = [properties objectForKey: @"_rev"];
    BOOL deleted = [[properties objectForKey: @"_deleted"] boolValue];
    TDRevision* rev = [[[TDRevision alloc] initWithDocID: _docID
                                                   revID: nil
                                                 deleted: deleted] autorelease];
    __block TDStatus status = 0;
    rev = [_server waitForDatabaseNamed: _databaseName to: ^(TDDatabase* db) {
        return [db putRevision: rev prevRevisionID: prevID allowConflict: NO status: &status];
    }];
    if (rev)
        _deleted = deleted;
    return status;
}


@end
