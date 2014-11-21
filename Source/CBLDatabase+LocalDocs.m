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
    KeyStore localDocs(_forest, "_local");
    Document doc = localDocs.get((forestdb::slice)docID.UTF8String);
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
        KeyStore localDocs(_forest, "_local");
        __block CBL_Revision* result = nil;
        *outStatus = [self _inTransaction: ^CBLStatus {
            KeyStoreWriter localWriter = (*_forestTransaction)(localDocs);
            NSData* json = revision.asCanonicalJSON;
            if (!json)
                return kCBLStatusBadJSON;
            forestdb::slice key(docID.UTF8String);
            Document doc = localWriter.get(key);
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
            localWriter.set(key, nsstring_slice(newRevID), forestdb::slice(json));
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

    KeyStore localDocs(_forest, "_local");
    return [self _inTransaction: ^CBLStatus {
        KeyStoreWriter localWriter = (*_forestTransaction)(localDocs);
        Document doc = localWriter.get(forestdb::slice(docID.UTF8String));
        if (!doc.exists())
            return kCBLStatusNotFound;
        else if (obeyMVCC && !$equal(revID, (NSString*)doc.meta()))
            return kCBLStatusConflict;
        else {
            localWriter.del(doc);
            return kCBLStatusOK;
        }
    }];
}


#pragma mark - INFO FOR KEY:


- (NSString*) infoForKey: (NSString*)key {
    KeyStore infoStore(_forest, "info");
    __block NSString* value = nil;
    [self _try: ^CBLStatus {
        Document doc = infoStore.get((forestdb::slice)key.UTF8String);
        value = (NSString*)doc.body();
        return kCBLStatusOK;
    }];
    return value;
}


- (CBLStatus) setInfo: (NSString*)info forKey: (NSString*)key {
    KeyStore infoStore(_forest, "info");
    return [self _inTransaction: ^CBLStatus {
        KeyStoreWriter infoWriter = (*_forestTransaction)(infoStore);
        infoWriter.set((forestdb::slice)key.UTF8String, (forestdb::slice)info.UTF8String);
        return kCBLStatusOK;
    }];
}


@end
