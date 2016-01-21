//
//  CBLForestBridge.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLForestBridge.h"
extern "C" {
#import "ExceptionUtils.h"
#import "CBLSymmetricKey.h"
}

using namespace cbforest;
using namespace couchbase_lite;


@implementation CBLForestBridge


static NSData* dataOfNode(const Revision* rev) {
    if (rev->inlineBody().buf)
        return rev->inlineBody().uncopiedNSData();
    try {
        return rev->readBody().copiedNSData();
    } catch (...) {
        return nil;
    }
}


+ (void) setEncryptionKey: (fdb_encryption_key*)fdbKey fromSymmetricKey: (CBLSymmetricKey*)key {
    if (key) {
        fdbKey->algorithm = FDB_ENCRYPTION_AES256;
        Assert(key.keyData.length <= sizeof(fdbKey->bytes));
        memcpy(fdbKey->bytes, key.keyData.bytes, sizeof(fdbKey->bytes));
    } else {
        fdbKey->algorithm = FDB_ENCRYPTION_NONE;
    }
}


+ (Database*) openDatabaseAtPath: (NSString*)path
                      withConfig: (Database::config&)config
                   encryptionKey: (CBLSymmetricKey*)key
                           error: (NSError**)outError
{
    [self setEncryptionKey: &config.encryption_key fromSymmetricKey: key];
    __block Database* db = NULL;
    BOOL ok = tryError(outError, ^{
        std::string pathStr(path.fileSystemRepresentation);
        try {
            db = new Database(pathStr, config);
        } catch (cbforest::error error) {
            if (error.status == FDB_RESULT_INVALID_COMPACTION_MODE
                        && config.compaction_mode == FDB_COMPACTION_AUTO) {
                // Databases created by earlier builds of CBL (pre-1.2) didn't have auto-compact.
                // Opening them with auto-compact causes this error. Upgrade such a database by
                // switching its compaction mode:
                Log(@"%@: Upgrading to auto-compact", self);
                config.compaction_mode = FDB_COMPACTION_MANUAL;
                db = new Database(pathStr, config);
                if (!(config.flags & FDB_OPEN_FLAG_RDONLY))
                    db->setCompactionMode(FDB_COMPACTION_AUTO);
            } else {
                throw error;
            }
        }
    });
    return ok ? db : nil;
}


+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (VersionedDocument&)doc
                                               revID: (NSString*)revID
                                            withBody: (BOOL)withBody
{
    CBL_MutableRevision* rev;
    NSString* docID = (NSString*)doc.docID();
    if (doc.revsAvailable()) {
        const Revision* revNode;
        if (revID)
            revNode = doc.get(revID);
        else {
            revNode = doc.currentRevision();
            if (revNode)
                revID = (NSString*)revNode->revID;
        }
        if (!revNode)
            return nil;
        rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                   revID: revID
                                                 deleted: revNode->isDeleted()];
        rev.sequence = revNode->sequence;
    } else {
        Assert(revID == nil || $equal(revID, (NSString*)doc.revID()));
        rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                   revID: (NSString*)doc.revID()
                                                 deleted: doc.isDeleted()];
        rev.sequence = doc.sequence();
    }
    if (withBody && ![self loadBodyOfRevisionObject: rev doc: doc])
        return nil;
    return rev;
}


+ (BOOL) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                              doc: (VersionedDocument&)doc
{
    const Revision* revNode = doc.get(rev.revID);
    if (!revNode)
        return NO;
    NSData* json = dataOfNode(revNode);
    if (!json)
        return NO;
    rev.sequence = revNode->sequence;
    rev.asJSON = json;
    return YES;
}


+ (NSMutableDictionary*) bodyOfNode: (const Revision*)rev {
    NSData* json = dataOfNode(rev);
    if (!json)
        return nil;
    NSMutableDictionary* properties = [CBLJSON JSONObjectWithData: json
                                                          options: NSJSONReadingMutableContainers
                                                            error: NULL];
    Assert(properties, @"Unable to parse doc from db: %@", json.my_UTF8ToString);
    NSString* revID = (NSString*)rev->revID;
    Assert(revID);

    const VersionedDocument* doc = (const VersionedDocument*)rev->owner;
    properties[@"_id"] = (NSString*)doc->docID();
    properties[@"_rev"] = revID;
    if (rev->isDeleted())
        properties[@"_deleted"] = $true;
    return properties;
}


+ (NSArray*) getCurrentRevisionIDs: (VersionedDocument&)doc includeDeleted: (BOOL)includeDeleted {
    NSMutableArray* currentRevIDs = $marray();
    auto revs = doc.currentRevisions();
    for (auto rev = revs.begin(); rev != revs.end(); ++rev)
        if (includeDeleted || !(*rev)->isDeleted())
            [currentRevIDs addObject: (NSString*)(*rev)->revID];
    return currentRevIDs;
}


+ (NSArray*) mapHistoryOfNode: (const Revision*)rev
                      through: (id(^)(const Revision*, BOOL *stop))block
{
    NSMutableArray* history = $marray();
    BOOL stop = NO;
    for (; rev && !stop; rev = rev->parent())
        [history addObject: block(rev, &stop)];
    return history;
}


+ (NSArray*) getRevisionHistoryOfNode: (const cbforest::Revision*)revNode
                         backToRevIDs: (NSSet*)ancestorRevIDs
{
    const VersionedDocument* doc = (const VersionedDocument*)revNode->owner;
    NSString* docID = (NSString*)doc->docID();
    return [self mapHistoryOfNode: revNode
                          through: ^id(const Revision *ancestor, BOOL *stop)
    {
        CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                revID: (NSString*)ancestor->revID
                                                              deleted: ancestor->isDeleted()];
        rev.missing = !ancestor->isBodyAvailable();
        if ([ancestorRevIDs containsObject: rev.revID])
            *stop = YES;
        return rev;
    }];
}


@end


namespace couchbase_lite {

    CBLStatus tryStatus(CBLStatus(^block)()) {
        try {
            return block();
        } catch (cbforest::error err) {
            return CBLStatusFromForestDBStatus(err.status);
        } catch (NSException* x) {
            MYReportException(x, @"CBL_ForestDBStorage");
            return kCBLStatusException;
        } catch (...) {
            Warn(@"Unknown C++ exception caught in CBL_ForestDBStorage");
            return kCBLStatusException;
        }
    }


    bool tryError(NSError** outError, void(^block)()) {
        CBLStatus status = tryStatus(^{
            block();
            return kCBLStatusOK;
        });
        return CBLStatusToOutNSError(status, outError);
    }


    CBLStatus CBLStatusFromForestDBStatus(int fdbStatus) {
        switch (fdbStatus) {
            case FDB_RESULT_SUCCESS:
                return kCBLStatusOK;
            case FDB_RESULT_KEY_NOT_FOUND:
            case FDB_RESULT_NO_SUCH_FILE:
                return kCBLStatusNotFound;
            case FDB_RESULT_RONLY_VIOLATION:
                return kCBLStatusForbidden;
            case FDB_RESULT_NO_DB_HEADERS:
            case FDB_RESULT_CRYPTO_ERROR:
                return kCBLStatusUnauthorized;     // assuming db is encrypted
            case FDB_RESULT_CHECKSUM_ERROR:
            case FDB_RESULT_FILE_CORRUPTION:
            case error::CorruptRevisionData:
                return kCBLStatusCorruptError;
            case error::BadRevisionID:
                return kCBLStatusBadID;
            default:
                return kCBLStatusDBError;
        }
    }

}
