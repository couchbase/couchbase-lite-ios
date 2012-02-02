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

#import "CollectionUtils.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "GTMNSData+zlib.h"


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
                            encoding: (TDAttachmentEncoding)encoding
                              length: (UInt64)length
                       encodedLength: (UInt64)encodedLength
                              revpos: (unsigned)revpos
{
    Assert(sequence > 0);
    Assert(name);
    Assert(!encoding || length==0 || encodedLength > 0);
    if(!keyData)
        return 500;
    if (encodedLength > length)
        Warn(@"Encoded attachment bigger than original: %llu > %llu for key %@",
             encodedLength, length, keyData);
    id encodedLengthObj = encoding ? $object(encodedLength) : nil;
    if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                                  "(sequence, filename, key, type, encoding, length, encoded_length, revpos) "
                                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                 $object(sequence), name, keyData, contentType,
                                 $object(encoding), $object(length), encodedLengthObj,
                                 $object(revpos)]) {
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
                    "(sequence, filename, key, type, encoding, encoded_Length, length, revpos) "
                    "SELECT ?, ?, key, type, encoding, encoded_Length, length, revpos "
                        "FROM attachments WHERE sequence=? AND filename=?",
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


- (NSData*) decodeAttachment: (NSData*)attachment encoding: (TDAttachmentEncoding)encoding {
    switch (encoding) {
        case kTDAttachmentEncodingNone:
            break;
        case kTDAttachmentEncodingGZIP:
            attachment = [NSData gtm_dataByInflatingData: attachment];
    }
    if (!attachment)
        Warn(@"Unable to decode attachment!");
    return attachment;
}


/** Returns the content and MIME type of an attachment */
- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                                type: (NSString**)outType
                            encoding: (TDAttachmentEncoding*)outEncoding
                              status: (TDStatus*)outStatus
{
    Assert(sequence > 0);
    Assert(filename);
    NSData* contents = nil;
    *outStatus = 500;
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT key, type, encoding FROM attachments WHERE sequence=? AND filename=?",
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
        
        TDAttachmentEncoding encoding = [r intForColumnIndex: 2];
        if (outEncoding)
            *outEncoding = encoding;
        else
            contents = [self decodeAttachment: contents encoding: encoding];
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
                      @"SELECT filename, key, type, encoding, length, encoded_length, revpos "
                       "FROM attachments WHERE sequence=?",
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
        NSData* data = nil;
        if (withContent) {
            data = [_attachments blobForKey: *(TDBlobKey*)keyData.bytes];
            if (!data)
                Warn(@"TDDatabase: Failed to get attachment for key %@", keyData);
        }
        
        NSString* encodingStr = nil;
        id encodedLength = nil;
        TDAttachmentEncoding encoding = [r intForColumnIndex: 3];
        if (encoding != kTDAttachmentEncodingNone) {
            if (withContent) {
                data = [self decodeAttachment: data encoding: encoding];
            } else {
                encodingStr = @"gzip";  // the only encoding I know
                encodedLength = $object([r longLongIntForColumnIndex: 5]);
            }
        }

        [attachments setObject: $dict({@"stub", (data ? nil : $true)},
                                      {@"data", (data ? [TDBase64 encode: data] : nil)},
                                      {@"digest", digestStr},
                                      {@"content_type", [r stringForColumnIndex: 2]},
                                      {@"encoding", encodingStr},
                                      {@"length", $object([r longLongIntForColumnIndex: 4])},
                                      {@"encoded_length", encodedLength},
                                      {@"revpos", $object([r intForColumnIndex: 6])})
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
                blobKey = [[self keyForAttachment: newContents] retain];    // store attachment!
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
            length = writer.length;
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
            
            // Handle encoded attachment:
            TDAttachmentEncoding encoding = kTDAttachmentEncodingNone;
            UInt64 encodedLength = 0;
            NSString* encodingStr = [newAttach objectForKey: @"encoding"];
            if (encodingStr) {
                if ($equal(encodingStr, @"gzip"))
                    encoding = kTDAttachmentEncodingGZIP;
                else
                    return 400;
                
                encodedLength = length;
                length = $castIf(NSNumber, [newAttach objectForKey: @"length"]).unsignedLongLongValue;
            }

            // Finally insert the attachment:
            status = [self insertAttachmentWithKey: blobKey
                                       forSequence: newSequence
                                             named: name
                                              type: [newAttach objectForKey: @"content_type"]
                                          encoding: encoding
                                            length: length
                                     encodedLength: encodedLength
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
                        encoding: (TDAttachmentEncoding)encoding
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
                    "(sequence, filename, key, type, encoding, encoded_length, length, revpos) "
                    "SELECT ?, filename, key, type, encoding, encoded_length, length, revpos "
                    "FROM attachments WHERE sequence=? AND filename != ?",
                                        $object(newRev.sequence), $object(oldRev.sequence),
                                        filename]) {
                *outStatus = 500;
                return nil;
            }
        }
        
        if (body) {
            // If not deleting, add a new attachment entry:
            UInt64 length = body.length, encodedLength = 0;
            if (encoding) {
                encodedLength = length;
                length = [self decodeAttachment: body encoding: encoding].length;
                if (length == 0 && encodedLength > 0) {
                    *outStatus = 400;     // failed to decode
                    return nil;
                }
            }
            *outStatus = [self insertAttachmentWithKey: [self keyForAttachment: body]
                                           forSequence: newRev.sequence
                                                 named: filename
                                                  type: contentType
                                              encoding: encoding
                                                length: body.length
                                         encodedLength: encodedLength
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
