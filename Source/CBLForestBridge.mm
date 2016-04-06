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
#import "CBLSpecialKey.h"
#import "forestdb.h"
}

namespace CBL {

C4Slice string2slice(UU NSString* str) {
    if (!str)
        return kC4SliceNull;
    const char* cstr = CFStringGetCStringPtr((__bridge CFStringRef)str, kCFStringEncodingUTF8);
    if (cstr)
        return (C4Slice){cstr, strlen(cstr)};
    else
        return data2slice([str dataUsingEncoding: NSUTF8StringEncoding]);
}

NSString* slice2string(C4Slice s) {
    if (!s.buf)
        return nil;
    return [[NSString alloc] initWithBytes: s.buf length: s.size encoding:NSUTF8StringEncoding];
}

NSData* slice2data(C4Slice s) {
    return [[NSData alloc] initWithBytes: s.buf length: s.size];
}

NSData* slice2dataNoCopy(C4Slice s) {
    return [[NSData alloc] initWithBytesNoCopy: (void*)s.buf length: s.size freeWhenDone: NO];
}

NSData* slice2dataAdopt(C4Slice s) {
    return [[NSData alloc] initWithBytesNoCopy: (void*)s.buf length: s.size freeWhenDone: YES];
}

id slice2jsonObject(C4Slice s, CBLJSONReadingOptions options) {
    NSData* json = slice2dataNoCopy(s);
    if (!json)
        return nil;
    return [CBLJSON JSONObjectWithData: json options: options error: NULL];
}


C4Slice id2JSONSlice(id obj) {
    if (!obj)
        return kC4SliceNull;
    return data2slice([CBLJSON dataWithJSONObject: obj
                                          options: CBLJSONWritingAllowFragments
                                            error: nil]);
}


static void addToKey(C4Key *key, UU id obj) {
    if ([obj isKindOfClass: [NSString class]]) {
        c4key_addString(key, string2slice(obj));
    } else if ([obj isKindOfClass: [NSNumber class]]) {
        if (obj == (__bridge id)kCFBooleanFalse)
            c4key_addBool(key, false);
        else if (obj == (__bridge id)kCFBooleanTrue)
            c4key_addBool(key, true);
        else
            c4key_addNumber(key, [obj doubleValue]);
    } else if ([obj isKindOfClass: [NSArray class]]) {
        c4key_beginArray(key);
        for (id item in obj)
            addToKey(key, item);
        c4key_endArray(key);
    } else if ([obj isKindOfClass: [NSDictionary class]]) {
        c4key_beginMap(key);
        [obj enumerateKeysAndObjectsUsingBlock:^(id dictKey, id dictValue, BOOL *stop) {
            c4key_addString(key, string2slice(dictKey));
            addToKey(key, dictValue);
        }];
        c4key_endMap(key);
    } else if ([obj isKindOfClass: [NSNull class]]) {
        c4key_addNull(key);
    } else {
        Assert(NO, @"emit() does not support keys of class %@", [obj class]);
    }
}

C4Key* id2key(UU id obj) {
    if (obj == nil) {
        return NULL;
    } else if ([obj isKindOfClass: [CBLSpecialKey class]]) {
        CBLSpecialKey* special = (CBLSpecialKey*)obj;
        NSString* text = special.text;
        if (text)
            return c4key_newFullTextString(string2slice(text), kC4SliceNull);
        else
            return c4key_newGeoJSON(data2slice(special.geoJSONData),
                                    geoRect2Area(special.rect));
    } else {
        C4Key *key = c4key_new();
        addToKey(key, obj);
        return key;
    }
}


static id key2id_(C4KeyReader *kr) {
    switch (c4key_peek(kr)) {
        case kC4Null:
            c4key_skipToken(kr);
            return [NSNull null];
        case kC4Bool:
            return c4key_readBool(kr) ? @YES : @NO;
        case kC4Number:
            return @(c4key_readNumber(kr));
        case kC4String: {
            C4SliceResult str = c4key_readString(kr);
            return [[NSString alloc] initWithBytesNoCopy: (void*)str.buf length: str.size
                                                encoding:NSUTF8StringEncoding freeWhenDone: YES];
        }
        case kC4Array: {
            NSMutableArray* a = [NSMutableArray new];
            c4key_skipToken(kr);
            while (c4key_peek(kr) != kC4EndSequence)
                [a addObject: key2id_(kr)];
            c4key_skipToken(kr);
            return a;
        }
        case kC4Map: {
            NSMutableDictionary* a = [NSMutableDictionary new];
            c4key_skipToken(kr);
            while (c4key_peek(kr) != kC4EndSequence) {
                NSString* key = key2id_(kr);
                a[key] = key2id_(kr);
            }
            c4key_skipToken(kr);
            return a;
        }
        default:
            Assert(NO, @"Invalid token %d in C4Key", (int)c4key_peek(kr));
            return nil;
    }
}

id key2id(C4KeyReader kr) {
    if (kr.bytes == NULL)
        return nil;
    return key2id_(&kr);
}


CBLStatus err2status(C4Error c4err) {
    if (c4err.code == 0)
        return kCBLStatusOK;
    switch (c4err.domain) {
        case HTTPDomain: {
            return (CBLStatus)c4err.code;
        }
        case POSIXDomain: {
        }
        case ForestDBDomain: {
            switch (c4err.code) {
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
                    return kCBLStatusCorruptError;
            }
        }
        case C4Domain: {
            switch (c4err.code) {
                case kC4ErrorCorruptRevisionData:
                    return kCBLStatusCorruptError;
                case kC4ErrorBadRevisionID:
                    return kCBLStatusBadID;
                case kC4ErrorCorruptIndexData:
                    return kCBLStatusCorruptError;
                case kC4ErrorIndexBusy:
                    return kCBLStatusDBBusy;
                case kC4ErrorAssertionFailed:
                    Assert(NO, @"Assertion failure in CBForest (check log)");
                    break;
                default: {
                    Warn(@"Unexpected CBForest error %d", c4err.code);
                }
            }
        }
    }
    return kCBLStatusDBError;
}


BOOL err2OutNSError(C4Error c4err, NSError** outError) {
    CBLStatusToOutNSError(err2status(c4err), outError);
    return NO;
}


C4EncryptionKey symmetricKey2Forest(CBLSymmetricKey* key) {
    C4EncryptionKey fdbKey;
    if (key) {
        fdbKey.algorithm = kC4EncryptionAES256;
        Assert(key.keyData.length == sizeof(fdbKey.bytes));
        memcpy(fdbKey.bytes, key.keyData.bytes, sizeof(fdbKey.bytes));
    } else {
        fdbKey.algorithm = kC4EncryptionNone;
    }
    return fdbKey;
}

} // end namespace CBL


@implementation CBLForestBridge


+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (C4Document*)doc
                                               docID: (UU NSString*)docID
                                               revID: (NSString*)revID
                                            withBody: (BOOL)withBody
                                              status: (CBLStatus*)outStatus
{
    BOOL deleted = (doc->selectedRev.flags & kRevDeleted) != 0;
    if (revID == nil)
        revID = slice2string(doc->selectedRev.revID);
    CBL_MutableRevision* result = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                       revID: revID
                                                                     deleted: deleted];
    result.sequence = doc->selectedRev.sequence;
    if (withBody) {
        *outStatus = [self loadBodyOfRevisionObject: result fromSelectedRevision: doc];
        if (CBLStatusIsError(*outStatus))
            result = nil;
    }
    return result;
}


+ (CBLStatus) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                  fromSelectedRevision: (C4Document*)doc
{
    C4Error c4err;
    if (!c4doc_loadRevisionBody(doc, &c4err))
        return err2status(c4err);
    rev.asJSON = slice2data(doc->selectedRev.body);
    rev.sequence = doc->selectedRev.sequence;
    return kCBLStatusOK;
}


+ (NSMutableDictionary*) bodyOfSelectedRevision: (C4Document*)doc {
    if (!c4doc_loadRevisionBody(doc, NULL))
        return nil;
    C4Slice body = doc->selectedRev.body;
    NSMutableDictionary* properties = slice2mutableDict(body);
    Assert(properties, @"Unable to parse doc from db: %.*s", body.size, body.buf);
    return properties;
}


+ (NSMutableArray*) getCurrentRevisionIDs: (C4Document*)doc
                           includeDeleted: (BOOL)includeDeleted
                            onlyConflicts: (BOOL)onlyConflicts
{
    NSMutableArray *revs = [[NSMutableArray alloc] init];
    do {
        if (onlyConflicts)
            onlyConflicts = NO;
        else if (!(doc->selectedRev.flags & kRevDeleted))
            [revs addObject: slice2string(doc->selectedRev.revID)];
    } while (c4doc_selectNextLeafRevision(doc, includeDeleted, false, NULL));
    return revs;
}


@end
