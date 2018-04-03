//
//  CBLDocumentChangeNotifier.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/3/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLDocumentChangeNotifier.h"
#import "CBLDatabase+Internal.h"
#import "CBLStringBytes.h"


@implementation CBLDocumentChangeNotifier
{
    NSString* _docID;
    CBLDatabase* _db;
    C4DocumentObserver* _obs;
}


- (instancetype) initWithDatabase: (CBLDatabase*)db
                       documentID: (NSString*)documentID
{
    self = [super init];
    if (self) {
        _db = db;
        _docID = documentID;
        CBLStringBytes bDocID(documentID);
        _obs = c4docobs_create(db.c4db, bDocID, docObserverCallback, (__bridge void *)self);
    }
    return self;
}


static void docObserverCallback(C4DocumentObserver* obs, C4Slice docID, C4SequenceNumber seq,
                                void *context)
{
    [(__bridge CBLDocumentChangeNotifier*)context postChange];
}


- (void) postChange {
    [self postChange: [[CBLDocumentChange alloc] initWithDatabase: _db documentID: _docID]];
}


- (void) stop {
    c4docobs_free(_obs);
    _obs = nullptr;
}


- (void) dealloc {
    c4docobs_free(_obs);
}


@end
