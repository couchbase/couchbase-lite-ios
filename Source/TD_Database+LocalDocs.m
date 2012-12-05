//
//  TD_Database+LocalDocs.m
//  TouchDB
//
//  Created by Jens Alfke on 1/10/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TD_Database+LocalDocs.h"
#import <TouchDB/TD_Revision.h>
#import "TD_Body.h"
#import "TDInternal.h"

#import "FMDatabase.h"


@implementation TD_Database (LocalDocs)


- (TD_Revision*) getLocalDocumentWithID: (NSString*)docID 
                            revisionID: (NSString*)revID
{
    TD_Revision* result = nil;
    FMResultSet *r = [_fmdb executeQuery: @"SELECT revid, json FROM localdocs WHERE docid=?",docID];
    if ([r next]) {
        NSString* gotRevID = [r stringForColumnIndex: 0];
        if (revID && !$equal(revID, gotRevID))
            return nil;
        NSData* json = [r dataNoCopyForColumnIndex: 1];
        NSMutableDictionary* properties;
        if (json.length==0 || (json.length==2 && memcmp(json.bytes, "{}", 2)==0))
            properties = $mdict();      // workaround for issue #44
        else {
            properties = [TDJSON JSONObjectWithData: json
                                            options:TDJSONReadingMutableContainers
                                              error: NULL];
            if (!properties)
                return nil;
        }
        properties[@"_id"] = docID;
        properties[@"_rev"] = gotRevID;
        result = [[TD_Revision alloc] initWithDocID: docID revID: gotRevID deleted:NO];
        result.properties = properties;
    }
    [r close];
    return result;
}


- (TD_Revision*) putLocalRevision: (TD_Revision*)revision
                  prevRevisionID: (NSString*)prevRevID
                          status: (TDStatus*)outStatus
{
    NSString* docID = revision.docID;
    if (![docID hasPrefix: @"_local/"]) {
        *outStatus = kTDStatusBadID;
        return nil;
    }
    if (!revision.deleted) {
        // PUT:
        NSData* json = [self encodeDocumentJSON: revision];
        NSString* newRevID;
        if (prevRevID) {
            unsigned generation = [TD_Revision generationFromRevID: prevRevID];
            if (generation == 0) {
                *outStatus = kTDStatusBadID;
                return nil;
            }
            newRevID = $sprintf(@"%d-local", ++generation);
            if (![_fmdb executeUpdate: @"UPDATE localdocs SET revid=?, json=? "
                                        "WHERE docid=? AND revid=?", 
                                       newRevID, json, docID, prevRevID]) {
                *outStatus = kTDStatusDBError;
                return nil;
            }
        } else {
            newRevID = @"1-local";
            // The docid column is unique so the insert will be a no-op if there is already
            // a doc with this ID.
            if (![_fmdb executeUpdate: @"INSERT OR IGNORE INTO localdocs (docid, revid, json) "
                                        "VALUES (?, ?, ?)",
                                   docID, newRevID, json]) {
                *outStatus = kTDStatusDBError;
                return nil;
            }
        }
        if (_fmdb.changes == 0) {
            *outStatus = kTDStatusConflict;
            return nil;
        }
        *outStatus = kTDStatusCreated;
        return [revision copyWithDocID: docID revID: newRevID];
        
    } else {
        // DELETE:
        *outStatus = [self deleteLocalDocumentWithID: docID revisionID: prevRevID];
        return *outStatus < 300 ? revision : nil;
    }
}


- (TDStatus) deleteLocalDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    if (!docID)
        return kTDStatusBadID;
    if (!revID) {
        // Didn't specify a revision to delete: kTDStatusNotFound or a kTDStatusConflict, depending
        return [self getLocalDocumentWithID: docID revisionID: nil] ? kTDStatusConflict : kTDStatusNotFound;
    }
    if (![_fmdb executeUpdate: @"DELETE FROM localdocs WHERE docid=? AND revid=?", docID, revID])
        return kTDStatusDBError;
    if (_fmdb.changes == 0)
        return [self getLocalDocumentWithID: docID revisionID: nil] ? kTDStatusConflict : kTDStatusNotFound;
    return kTDStatusOK;
}


@end
