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

#import <CBForest/CBForest.h>


// Close the local docs db after its inactive this many seconds
#define kCloseDelay 15.0


@implementation CBLDatabase (LocalDocs)


- (CBForestDB*) localDocs {
    if (!_localDocs) {
        NSString* path = [_dir stringByAppendingPathComponent: @"local.forest"];
        _localDocs = [[CBForestDB alloc] initWithFile: path options: kCBForestDBCreate
                                                error: NULL];
        LogTo(CBLDatabase, @"%@: Opened _local docs db", self);
    }
    [self closeLocalDocsSoon];
    return _localDocs;
}

- (void) closeLocalDocs {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeLocalDocs)
                                               object: nil];
    if (_localDocs) {
        [_localDocs close];
        _localDocs = nil;
        LogTo(CBLDatabase, @"%@: Closed _local docs db", self);
    }
}

- (void) closeLocalDocsSoon {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeLocalDocs)
                                               object: nil];
    [self performSelector: @selector(closeLocalDocs) withObject: nil afterDelay: kCloseDelay];
}


static NSString* getDocRevID(CBForestDocument* doc) {
    NSData* meta = doc.metadata;
    if (!meta)
        return nil;
    return [[NSString alloc] initWithData: meta encoding: NSUTF8StringEncoding];
}


static NSDictionary* getDocProperties(CBForestDocument* doc) {
    NSData* bodyData = [doc readBody: NULL];
    if (!bodyData)
        return nil;
    return [CBLJSON JSONObjectWithData: bodyData options: 0 error: NULL];
}


- (CBL_Revision*) getLocalDocumentWithID: (NSString*)docID 
                              revisionID: (NSString*)revID
{
    if (![docID hasPrefix: @"_local/"])
        return nil;
    CBForestDocument* doc = [self.localDocs documentWithID: docID options: 0 error: NULL];
    NSString* gotRevID = getDocRevID(doc);
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
                            status: (CBLStatus*)outStatus
{
    NSString* docID = revision.docID;
    if (![docID hasPrefix: @"_local/"]) {
        *outStatus = kCBLStatusBadID;
        return nil;
    }
    if (revision.deleted) {
        // DELETE:
        *outStatus = [self deleteLocalDocumentWithID: docID revisionID: prevRevID];
        return *outStatus < 300 ? revision : nil;
    } else {
        // PUT:
        NSError* error;
        CBForestDocument* doc = [self.localDocs documentWithID: docID options: 0 error: &error];
        if (!doc && error && error.code != kCBForestErrorNotFound) {
            *outStatus = kCBLStatusDBError;
            return nil;
        }

        unsigned generation = 0;
        if (prevRevID) {
            if (!$equal(prevRevID, getDocRevID(doc))) {
                *outStatus = kCBLStatusConflict;
                return nil;
            }
            generation = [CBL_Revision generationFromRevID: prevRevID];
            if (generation == 0) {
                *outStatus = kCBLStatusBadID;
                return nil;
            }
        } else {
            if (doc) {
                *outStatus = kCBLStatusConflict;
                return nil;
            }
            doc = [self.localDocs makeDocumentWithID: docID];
        }
        NSString* newRevID = $sprintf(@"%d-local", ++generation);

        if (![doc writeBody: [self encodeDocumentJSON: revision]
                   metadata: [newRevID dataUsingEncoding: NSUTF8StringEncoding]
                      error: &error]) {
            *outStatus = kCBLStatusDBError;
            return nil;
        }
        [_localDocs commit: NULL];
        *outStatus = kCBLStatusCreated;
        return [revision mutableCopyWithDocID: docID revID: newRevID];
    }
}


- (CBLStatus) deleteLocalDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    if (![docID hasPrefix: @"_local/"])
        return kCBLStatusBadID;
    if (!revID) {
        // Didn't specify a revision to delete: kCBLStatusNotFound or a kCBLStatusConflict, depending
        return [self getLocalDocumentWithID: docID revisionID: nil] ? kCBLStatusConflict : kCBLStatusNotFound;
    }

    NSError* error;
    CBForestDocument* doc = [self.localDocs documentWithID: docID options: 0 error: &error];
    if (!doc) {
        if (!error || error.code == kCBForestErrorNotFound)
            return kCBLStatusNotFound;
        else
            return kCBLStatusDBError;
    }
    if (!$equal(getDocRevID(doc), revID))
        return kCBLStatusConflict;
    if (![self.localDocs deleteDocument: doc error: &error])
        return kCBLStatusDBError;
    [_localDocs commit: NULL];
    return kCBLStatusOK;
}


#pragma mark - INFO FOR KEY:


static NSData* infoKey(NSString* key) {
    return [[@"_info/" stringByAppendingString: key] dataUsingEncoding: NSUTF8StringEncoding];
}

- (NSString*) infoForKey: (NSString*)key {
    NSData* value;
    if (![self.localDocs getValue: &value meta: NULL forKey: infoKey(key) error: NULL] || !value)
        return nil;
    return [[NSString alloc] initWithData: value encoding: NSUTF8StringEncoding];
}

- (CBLStatus) setInfo: (NSString*)info forKey: (NSString*)key {
    if (![self.localDocs setValue: [info dataUsingEncoding: NSUTF8StringEncoding]
                             meta: NULL
                           forKey: infoKey(key)
                            error: NULL])
        return kCBLStatusDBError;
    return kCBLStatusOK;
}


@end
