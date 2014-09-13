//
//  CBLDatabase+LocalDocs.m
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

#import "CBLDatabase+LocalDocs.h"
#import "CBL_Revision.h"
#import "CBL_Body.h"
#import "CBLInternal.h"

#import "FMDatabase.h"


@implementation CBLDatabase (LocalDocs)


- (CBL_Revision*) getLocalDocumentWithID: (NSString*)docID 
                              revisionID: (NSString*)revID
{
    CBL_MutableRevision* result = nil;
    CBL_FMResultSet *r = [_fmdb executeQuery: @"SELECT revid, json FROM localdocs WHERE docid=?",docID];
    if ([r next]) {
        NSString* gotRevID = [r stringForColumnIndex: 0];
        if (revID && !$equal(revID, gotRevID))
            return nil;
        NSData* json = [r dataNoCopyForColumnIndex: 1];
        NSMutableDictionary* properties;
        if (json.length==0 || (json.length==2 && memcmp(json.bytes, "{}", 2)==0))
            properties = $mdict();      // workaround for issue #44
        else {
            properties = [CBLJSON JSONObjectWithData: json
                                            options:CBLJSONReadingMutableContainers
                                              error: NULL];
            if (!properties)
                return nil;
        }
        properties[@"_id"] = docID;
        properties[@"_rev"] = gotRevID;
        result = [[CBL_MutableRevision alloc] initWithDocID: docID revID: gotRevID deleted:NO];
        result.properties = properties;
    }
    [r close];
    return result;
}


- (CBL_Revision*) putLocalRevision: (CBL_Revision*)revision
                  prevRevisionID: (NSString*)prevRevID
                          status: (CBLStatus*)outStatus
{
    NSString* docID = revision.docID;
    if (![docID hasPrefix: @"_local/"]) {
        *outStatus = kCBLStatusBadID;
        return nil;
    }
    if (!revision.deleted) {
        // PUT:
        NSData* json = [self encodeDocumentJSON: revision];
        if (!json) {
            *outStatus = kCBLStatusBadJSON;
            return nil;
        }
        
        NSString* newRevID;
        if (prevRevID) {
            unsigned generation = [CBL_Revision generationFromRevID: prevRevID];
            if (generation == 0) {
                *outStatus = kCBLStatusBadID;
                return nil;
            }
            newRevID = $sprintf(@"%d-local", ++generation);
            if (![_fmdb executeUpdate: @"UPDATE localdocs SET revid=?, json=? "
                                        "WHERE docid=? AND revid=?", 
                                       newRevID, json, docID, prevRevID]) {
                *outStatus = self.lastDbError;
                return nil;
            }
        } else {
            newRevID = @"1-local";
            // The docid column is unique so the insert will be a no-op if there is already
            // a doc with this ID.
            if (![_fmdb executeUpdate: @"INSERT OR IGNORE INTO localdocs (docid, revid, json) "
                                        "VALUES (?, ?, ?)",
                                   docID, newRevID, json]) {
                *outStatus = self.lastDbError;
                return nil;
            }
        }
        if (_fmdb.changes == 0) {
            *outStatus = kCBLStatusConflict;
            return nil;
        }
        *outStatus = kCBLStatusCreated;
        return [revision mutableCopyWithDocID: docID revID: newRevID];
        
    } else {
        // DELETE:
        *outStatus = [self deleteLocalDocumentWithID: docID revisionID: prevRevID];
        return *outStatus < 300 ? revision : nil;
    }
}


- (CBLStatus) deleteLocalDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    if (!docID)
        return kCBLStatusBadID;
    if (!revID) {
        // Didn't specify a revision to delete: kCBLStatusNotFound or a kCBLStatusConflict, depending
        return [self getLocalDocumentWithID: docID revisionID: nil] ? kCBLStatusConflict : kCBLStatusNotFound;
    }
    if (![_fmdb executeUpdate: @"DELETE FROM localdocs WHERE docid=? AND revid=?", docID, revID])
        return self.lastDbError;
    if (_fmdb.changes == 0)
        return [self getLocalDocumentWithID: docID revisionID: nil] ? kCBLStatusConflict : kCBLStatusNotFound;
    return kCBLStatusOK;
}


@end
