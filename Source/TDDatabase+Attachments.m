//
//  TDDatabase+Attachments.m
//  TouchDB
//
//  Created by Jens Alfke on 12/19/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  http://wiki.apache.org/couchdb/HTTP_Document_API#Attachments

/*
    Here's what an actual _attachments object from CouchDB 1.2 looks like.
    The "revpos" and "digest" attributes aren't documented in the wiki (yet).
 
    "_attachments":{
        "index.txt":{"content_type":"text/plain", "revpos":1,
                     "digest":"md5-muNoTiLXyJYP9QkvPukNng==", "length":9, "stub":true}}
*/

#import "TDDatabase.h"
#import "TDBlobStore.h"
#import "TDBase64.h"
#import "TDInternal.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "CollectionUtils.h"


@implementation TDDatabase (Attachments)


- (BOOL) insertAttachment: (NSData*)contents
              forSequence: (SequenceNumber)sequence
                    named: (NSString*)name
                     type: (NSString*)contentType
                   revpos: (unsigned)revpos
{
    Assert(contents);
    Assert(sequence > 0);
    Assert(name);
    TDBlobKey key;
    if (![_attachments storeBlob: contents creatingKey: &key])
        return NO;
    NSData* keyData = [NSData dataWithBytes: &key length: sizeof(key)];
    return [_fmdb executeUpdate: @"INSERT INTO attachments "
                                  "(sequence, filename, key, type, length, revpos) "
                                  "VALUES (?, ?, ?, ?, ?, ?)",
                                 $object(sequence), name, keyData, contentType,
                                 $object(contents.length), $object(revpos)];
}


- (TDStatus) copyAttachmentNamed: (NSString*)name
                    fromSequence: (SequenceNumber)fromSequence
                      toSequence: (SequenceNumber)toSequence
{
    Assert(name);
    Assert(toSequence > 0);
    Assert(toSequence > fromSequence);
    if (fromSequence <= 0)
        return 404;
    if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                                "(sequence, filename, key, type, length, revpos) "
                                  "SELECT ?, ?, key, type, length, revpos FROM attachments "
                                    "WHERE sequence=? AND filename=?",
                                $object(toSequence), name,
                                $object(fromSequence), name]) {
        return 500;
    }
    if (_fmdb.changes == 0) {
        // Oops. This means a glitch in our attachment-management or pull code,
        // or else a bug in the upstream server.
        Warn(@"Can't find inherited attachment '%@' from seq#%lld to copy to #%lld",
             name, fromSequence, toSequence);
        return 404;         // Fail if there is no such attachment on fromSequence
    }
    return 200;
}


/** Returns the content and MIME type of an attachment */
- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                                type: (NSString**)outType
                              status: (TDStatus*)outStatus
{
    Assert(sequence > 0);
    Assert(filename);
    NSData* contents = nil;
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT key, type FROM attachments WHERE sequence=? AND filename=?",
                      $object(sequence), filename];
    if (!r) {
        *outStatus = 500;
        return nil;
    }
    if (![r next]) {
        *outStatus = 404;
        goto exit;
    }
    NSData* keyData = [r dataForColumnIndex: 0];
    if (keyData.length != sizeof(TDBlobKey)) {
        Warn(@"%@: Attachment %lld.'%@' has bogus key size %d",
             self, sequence, filename, keyData.length);
        *outStatus = 500;
        goto exit;
    }
    contents = [_attachments blobForKey: *(TDBlobKey*)keyData.bytes];
    if (!contents) {
        Warn(@"%@: Failed to load attachment %lld.'%@'", self, sequence, filename);
        *outStatus = 500;
    } else {
        *outStatus = 200;
    }
    if (outType)
        *outType = [r stringForColumnIndex: 1];
exit:
    [r close];
    return contents;
}


/** Constructs an "_attachments" dictionary for a revision, to be inserted in its JSON body. */
- (NSDictionary*) getAttachmentDictForSequence: (SequenceNumber)sequence
                                   withContent: (BOOL)withContent
{
    Assert(sequence > 0);
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT filename, key, type, length, revpos FROM attachments "
                       "WHERE sequence=?",
                      $object(sequence)];
    if (!r)
        return nil;
    if (![r next]) {
        [r close];
        return nil;
    }
    NSMutableDictionary* attachments = $mdict();
    do {
        NSData* keyData = [r dataForColumnIndex: 1];
        NSString* digestStr = [@"sha1-" stringByAppendingString: [TDBase64 encode: keyData]];
        NSString* dataBase64 = nil;
        if (withContent) {
            NSData* data = [_attachments blobForKey: *(TDBlobKey*)keyData.bytes];
            if (data)
                dataBase64 = [TDBase64 encode: data];
            else
                Warn(@"TDDatabase: Failed to get attachment for key %@", keyData);
        }
        [attachments setObject: $dict({@"stub", (dataBase64 ? nil : $true)},
                                      {@"data", dataBase64},
                                      {@"digest", digestStr},
                                      {@"content_type", [r stringForColumnIndex: 2]},
                                      {@"length", $object([r longLongIntForColumnIndex: 3])},
                                      {@"revpos", $object([r intForColumnIndex: 4])})
                        forKey: [r stringForColumnIndex: 0]];
    } while ([r next]);
    [r close];
    return attachments;
}


- (TDStatus) processAttachmentsForRevision: (TDRevision*)rev
                        withParentSequence: (SequenceNumber)parentSequence
{
    Assert(rev);
    SequenceNumber newSequence = rev.sequence;
    Assert(newSequence > 0);
    Assert(newSequence > parentSequence);
    
    // If there are no attachments in the new rev, there's nothing to do:
    NSDictionary* newAttachments = [rev.properties objectForKey: @"_attachments"];
    if (newAttachments.count == 0 || rev.deleted)
        return 200;
    
    for (NSString* name in newAttachments) {
        NSDictionary* newAttach = [newAttachments objectForKey: name];
        NSString* newContentsBase64 = [newAttach objectForKey: @"data"];
        if (newContentsBase64) {
            // New item contains data, so insert it. First decode the data:
            NSData* newContents = [TDBase64 decode: newContentsBase64];
            if (!newContents)
                return 400;
            
            // Now determine the revpos, i.e. generation # this was added in. Usually this is
            // implicit, but a rev being pulled in replication will have it set already.
            unsigned generation = rev.generation;
            Assert(generation > 0, @"Missing generation in rev %@", rev);
            NSNumber* revposObj = $castIf(NSNumber, [newAttach objectForKey: @"revpos"]);
            unsigned revpos = revposObj ? (unsigned)revposObj.intValue : generation;
            if (revpos > generation)
                return 400;

            // Finally insert the attachment:
            if (![self insertAttachment: newContents
                            forSequence: newSequence
                                  named: name
                                   type: [newAttach objectForKey: @"content_type"]
                                 revpos: revpos])
                return 500;
        } else {
            // It's just a stub, so copy the previous revision's attachment entry:
            //? Should I enforce that the type and digest (if any) match?
            TDStatus status = [self copyAttachmentNamed: name
                                           fromSequence: parentSequence
                                             toSequence: newSequence];
            if (status >= 300)
                return status;
        }
    }
    return 200;
}


- (TDStatus) garbageCollectAttachments {
    // First delete attachment rows for already-cleared revisions:
    // OPT: Could start after last sequence# we GC'd up to
    [_fmdb executeUpdate:  @"DELETE FROM attachments WHERE sequence IN "
                            "(SELECT sequence from revs WHERE json IS null)"];
    
    // Now collect all remaining attachment IDs and tell the store to delete all but these:
    FMResultSet* r = [_fmdb executeQuery: @"SELECT DISTINCT key FROM attachments"];
    if (!r)
        return 500;
    NSMutableSet* allKeys = [NSMutableSet set];
    while ([r next]) {
        [allKeys addObject: [r dataForColumnIndex: 0]];
    }
    [r close];
    NSInteger numDeleted = [_attachments deleteBlobsExceptWithKeys: allKeys];
    if (numDeleted < 0)
        return 500;
    Log(@"Deleted %d attachments", numDeleted);
    return 200;
}


@end
