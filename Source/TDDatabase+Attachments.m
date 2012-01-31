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

#import "TDDatabase+Attachments.h"
#import "TDDatabase+Insertion.h"
#import "TDBase64.h"
#import "TDBlobStore.h"
#import "TDBody.h"
#import "TDInternal.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "CollectionUtils.h"


NSString* const kTDAttachmentBlobKeyProperty = @"__tdblobkey__";


@implementation TDDatabase (Attachments)


- (TDBlobStoreWriter*) attachmentWriter {
    return [[[TDBlobStoreWriter alloc] initWithStore: _attachments] autorelease];
}


- (void) rememberAttachmentWritersForDigests: (NSDictionary*)blobsByDigests {
    if (!_pendingAttachmentsByDigest)
        _pendingAttachmentsByDigest = [[NSMutableDictionary alloc] init];
    [_pendingAttachmentsByDigest addEntriesFromDictionary: blobsByDigests];
}


- (NSData*) keyForAttachment: (NSData*)contents {
    Assert(contents);
    TDBlobKey key;
    if (![_attachments storeBlob: contents creatingKey: &key])
        return nil;
    return [NSData dataWithBytes: &key length: sizeof(key)];
}


- (TDStatus) insertAttachmentWithKey: (NSData*)keyData
                         forSequence: (SequenceNumber)sequence
                               named: (NSString*)name
                                type: (NSString*)contentType
                              length: (UInt64)length
                              revpos: (unsigned)revpos
{
    Assert(sequence > 0);
    Assert(name);
    if(!keyData)
        return 500;
    if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                                  "(sequence, filename, key, type, length, revpos) "
                                  "VALUES (?, ?, ?, ?, ?, ?)",
                                 $object(sequence), name, keyData, contentType,
                                 $object(length), $object(revpos)]) {
        return 500;
    }
    return 201;
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
    *outStatus = 500;
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT key, type FROM attachments WHERE sequence=? AND filename=?",
                      $object(sequence), filename];
    if (!r)
        return nil;
    @try {
        if (![r next]) {
            *outStatus = 404;
            return nil;
        }
        NSData* keyData = [r dataNoCopyForColumnIndex: 0];
        if (keyData.length != sizeof(TDBlobKey)) {
            Warn(@"%@: Attachment %lld.'%@' has bogus key size %d",
                 self, sequence, filename, keyData.length);
            return nil;
        }
        contents = [_attachments blobForKey: *(TDBlobKey*)keyData.bytes];
        if (!contents) {
            Warn(@"%@: Failed to load attachment %lld.'%@'", self, sequence, filename);
            return nil;
        }
        *outStatus = 200;
        if (outType)
            *outType = [r stringForColumnIndex: 1];
    } @finally {
        [r close];
    }
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
        NSData* keyData = [r dataNoCopyForColumnIndex: 1];
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
        TDStatus status;
        NSDictionary* newAttach = [newAttachments objectForKey: name];
        NSData* blobKey = nil;
        UInt64 length;
        
        NSString* newContentsBase64 = $castIf(NSString, [newAttach objectForKey: @"data"]);
        if (newContentsBase64) {
            // If there's inline attachment data, decode and store it:
            @autoreleasepool {
                NSData* newContents = [TDBase64 decode: newContentsBase64];
                if (!newContents)
                    return 400;
                length = newContents.length;
                blobKey = [[self keyForAttachment: newContents] retain];
            }
            [blobKey autorelease];
        } else if ([[newAttach objectForKey: @"follows"] isEqual: $true]) {
            // "follows" means the uploader provided the attachment in a separate MIME part.
            // This means it's already been registered in _pendingAttachmentsByDigest;
            // I just need to look it up by its "digest" property and install it into the store:
            NSString* digest = $castIf(NSString, [newAttach objectForKey: @"digest"]);
            if (!digest)
                return 400;
            TDBlobStoreWriter *writer = [_pendingAttachmentsByDigest objectForKey: digest];
            if (![writer install])
                return 500;
            TDBlobKey key = writer.blobKey;
            blobKey = [NSData dataWithBytes: &key length: sizeof(key)];
            length = $castIf(NSNumber, [newAttach objectForKey: @"length"]).unsignedLongLongValue;
        }
        
        if (blobKey) {
            // New item contains data, so insert it.
            // First determine the revpos, i.e. generation # this was added in. Usually this is
            // implicit, but a rev being pulled in replication will have it set already.
            unsigned generation = rev.generation;
            Assert(generation > 0, @"Missing generation in rev %@", rev);
            NSNumber* revposObj = $castIf(NSNumber, [newAttach objectForKey: @"revpos"]);
            unsigned revpos = revposObj ? (unsigned)revposObj.intValue : generation;
            if (revpos > generation)
                return 400;

            // Finally insert the attachment:
            status = [self insertAttachmentWithKey: blobKey
                                       forSequence: newSequence
                                             named: name
                                              type: [newAttach objectForKey: @"content_type"]
                                            length: length
                                            revpos: revpos];
        } else {
            // It's just a stub, so copy the previous revision's attachment entry:
            //? Should I enforce that the type and digest (if any) match?
            status = [self copyAttachmentNamed: name
                                  fromSequence: parentSequence
                                    toSequence: newSequence];
        }
        if (status >= 300)
            return status;
    }
    return 200;
}


- (TDRevision*) updateAttachment: (NSString*)filename
                            body: (NSData*)body
                            type: (NSString*)contentType
                         ofDocID: (NSString*)docID
                           revID: (NSString*)oldRevID
                          status: (TDStatus*)outStatus
{
    *outStatus = 400;
    if (filename.length == 0 || (body && !contentType) || (oldRevID && !docID) || (body && !docID))
        return nil;
    
    [self beginTransaction];
    @try {
        TDRevision* oldRev = [[TDRevision alloc] initWithDocID: docID revID: oldRevID deleted: NO];
        if (oldRevID) {
            // Load existing revision if this is a replacement:
            *outStatus = [self loadRevisionBody: oldRev options: 0];
            if (*outStatus >= 300) {
                if (*outStatus == 404 && [self existsDocumentWithID: docID revisionID: nil])
                    *outStatus = 409;   // if some other revision exists, it's a conflict
                return nil;
            }
            NSDictionary* attachments = [oldRev.properties objectForKey: @"_attachments"];
            if (!body && ![attachments objectForKey: filename]) {
                *outStatus = 404;
                return nil;
            }
            // Remove the _attachments stubs so putRevision: doesn't copy the rows for me
            // OPT: Would be better if I could tell loadRevisionBody: not to add it
            if (attachments) {
                NSMutableDictionary* properties = [oldRev.properties mutableCopy];
                [properties removeObjectForKey: @"_attachments"];
                oldRev.body = [TDBody bodyWithProperties: properties];
                [properties release];
            }
        } else {
            // If this creates a new doc, it needs a body:
            oldRev.body = [TDBody bodyWithProperties: $dict()];
        }
        
        // Create a new revision:
        TDRevision* newRev = [self putRevision: oldRev prevRevisionID: oldRevID
                                 allowConflict: NO status: outStatus];
        if (!newRev)
            return nil;
        
        if (oldRevID) {
            // Copy all attachment rows _except_ for the one being updated:
            if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                                        "(sequence, filename, key, type, length, revpos) "
                                          "SELECT ?, filename, key, type, length, revpos FROM attachments "
                                            "WHERE sequence=? AND filename != ?",
                                        $object(newRev.sequence), $object(oldRev.sequence),
                                        filename]) {
                *outStatus = 500;
                return nil;
            }
        }
        
        if (body) {
            // If not deleting, add a new attachment entry:
            *outStatus = [self insertAttachmentWithKey: [self keyForAttachment: body]
                                           forSequence: newRev.sequence
                                                 named: filename
                                                  type: contentType
                                                length: body.length
                                                revpos: newRev.generation];
            if (*outStatus >= 300)
                return nil;
        }
        
        *outStatus = body ? 201 : 200;
        return newRev;
    } @finally {
        [self endTransaction: (*outStatus < 300)];
    }
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
