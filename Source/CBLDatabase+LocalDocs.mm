//
//  CBLDatabase+LocalDocs.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/10/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

extern "C" {
#import "CBLDatabase+LocalDocs.h"
#import "CBL_Revision.h"
#import "CBL_Body.h"
#import "CBLInternal.h"
}
#import <CBForest/CBForest.hh>
using namespace forestdb;


// Close the local docs db after it's inactive this many seconds
#define kCloseDelay 15.0


@implementation CBLDatabase (LocalDocs)


- (Database*) localDocs {
    if (!_localDocs) {
        NSString* path = [_dir stringByAppendingPathComponent: @"local.forest"];
        Database::config config = Database::defaultConfig();
        config.buffercache_size = 128*1024;
        config.wal_threshold = 128;
//      config.wal_flush_before_commit = true;  // Can't use yet; see MB-11514
        config.seqtree_opt = false;
        _localDocs = new Database(path.fileSystemRepresentation, FDB_OPEN_FLAG_CREATE, config);
        LogTo(CBLDatabase, @"%@: Opened _local docs db", self);
    }
    [self closeLocalDocsSoon];
    return _localDocs;
}

- (void) closeLocalDocs {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeLocalDocs)
                                               object: nil];
    if (_localDocs) {
        delete _localDocs;
        _localDocs = nil;
        LogTo(CBLDatabase, @"%@: Closed _local docs db", self);
    }
}

- (void) closeLocalDocsSoon {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeLocalDocs)
                                               object: nil];
    [self performSelector: @selector(closeLocalDocs) withObject: nil afterDelay: kCloseDelay];
}


static NSDictionary* getDocProperties(const Document& doc) {
    NSData* bodyData = doc.body().uncopiedNSData();
    if (!bodyData)
        return nil;
    return [CBLJSON JSONObjectWithData: bodyData options: 0 error: NULL];
}


- (CBL_Revision*) getLocalDocumentWithID: (NSString*)docID 
                              revisionID: (NSString*)revID
{
    if (![docID hasPrefix: @"_local/"])
        return nil;
    Document doc = self.localDocs->get((forestdb::slice)docID.UTF8String);
    if (!doc.exists())
        return nil;
    NSString* gotRevID = (NSString*)doc.meta();
    if (revID && !$equal(revID, gotRevID))
        return nil;
    NSMutableDictionary* properties = [getDocProperties(doc) mutableCopy];
    if (!properties)
        return nil;
    properties[@"_id"] = docID;
    properties[@"_rev"] = gotRevID;
    CBL_MutableRevision* result = [[CBL_MutableRevision alloc] initWithDocID: docID revID: gotRevID
                                                                     deleted: NO];
    result.properties = properties;
    return result;
}


- (CBL_Revision*) putLocalRevision: (CBL_Revision*)revision
                    prevRevisionID: (NSString*)prevRevID
                          obeyMVCC: (BOOL)obeyMVCC
                            status: (CBLStatus*)outStatus
{
    NSString* docID = revision.docID;
    if (![docID hasPrefix: @"_local/"]) {
        *outStatus = kCBLStatusBadID;
        return nil;
    }
    if (revision.deleted) {
        // DELETE:
        *outStatus = [self deleteLocalDocumentWithID: docID
                                          revisionID: prevRevID
                                            obeyMVCC: obeyMVCC];
        return *outStatus < 300 ? revision : nil;
    } else {
        // PUT:
        __block CBL_Revision* result = nil;
        *outStatus = [self _try: ^CBLStatus {
            Transaction t(self.localDocs);
            forestdb::slice key(docID.UTF8String);
            Document doc = _localDocs->get(key);
            unsigned generation = [CBL_Revision generationFromRevID: prevRevID];
            if (obeyMVCC) {
                if (prevRevID) {
                    if (!$equal(prevRevID, (NSString*)doc.meta()))
                        return kCBLStatusConflict;
                    if (generation == 0)
                        return kCBLStatusBadID;
                } else {
                    if (doc.exists())
                        return kCBLStatusConflict;
                }
            }
            NSString* newRevID = $sprintf(@"%d-local", ++generation);
            t.set(key, nsstring_slice(newRevID), forestdb::slice(revision.asCanonicalJSON));
            result = [revision mutableCopyWithDocID: docID revID: newRevID];
            return kCBLStatusCreated;
        }];
        return result;
    }
}


- (CBLStatus) deleteLocalDocumentWithID: (NSString*)docID
                             revisionID: (NSString*)revID
                               obeyMVCC: (BOOL)obeyMVCC
{
    if (![docID hasPrefix: @"_local/"])
        return kCBLStatusBadID;
    if (obeyMVCC && !revID) {
        // Didn't specify a revision to delete: kCBLStatusNotFound or a kCBLStatusConflict, depending
        return [self getLocalDocumentWithID: docID revisionID: nil] ? kCBLStatusConflict : kCBLStatusNotFound;
    }

    return [self _try: ^CBLStatus {
        Transaction t(self.localDocs);
        Document doc = _localDocs->get(forestdb::slice(docID.UTF8String));
        if (!doc.exists())
            return kCBLStatusNotFound;
        else if (obeyMVCC && !$equal(revID, (NSString*)doc.meta()))
            return kCBLStatusConflict;
        else {
            t.del(doc);
            return kCBLStatusOK;
        }
    }];
}


#pragma mark - INFO FOR KEY:


- (NSString*) infoForKey: (NSString*)key {
    __block NSString* value = nil;
    [self _try: ^CBLStatus {
        Document doc = self.localDocs->get((forestdb::slice)key.UTF8String);
        value = (NSString*)doc.body();
        return kCBLStatusOK;
    }];
    return value;
}


- (CBLStatus) setInfo: (NSString*)info forKey: (NSString*)key {
    return [self _try: ^CBLStatus {
        Transaction t(self.localDocs);
        t.set((forestdb::slice)key.UTF8String, (forestdb::slice)info.UTF8String);
        return kCBLStatusOK;
    }];
}


@end
