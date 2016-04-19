//
//  CBLDatabase+REST.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/7/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase+REST.h"
#import "CBLDatabase+Insertion.h"
#import "CBLBase64.h"
#import "CBL_BlobStore.h"
#import "CBL_BlobStoreWriter.h"
#import "CBL_Attachment.h"
#import "CBL_Body.h"
#import "CBLMultipartWriter.h"
#import "CBLMisc.h"
#import "CBLInternal.h"
#import "CBLGZip.h"


@implementation CBLDatabase (REST)


#pragma mark - DESIGN DOCS:


- (id) getDesignDocFunction: (NSString*)fnName
                        key: (NSString*)key
                   language: (NSString**)outLanguage
{
    NSArray* path = [fnName componentsSeparatedByString: @"/"];
    if (path.count != 2)
        return nil;
    CBLStatus status;
    CBL_Revision* rev = [self getDocumentWithID: [@"_design/" stringByAppendingString: path[0]]
                                    revisionID: nil
                                       withBody: YES
                                         status: &status];
    if (!rev)
        return nil;
    *outLanguage = rev[@"language"] ?: @"javascript";
    NSDictionary* container = $castIf(NSDictionary, rev[key]);
    return container[path[1]];
}


- (CBLFilterBlock) compileFilterNamed: (NSString*)filterName status: (CBLStatus*)outStatus {
    id<CBLFilterCompiler> compiler = [CBLDatabase filterCompiler];
    if (!compiler) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    NSString* language;
    NSString* source = $castIf(NSString, [self getDesignDocFunction: filterName
                                                                key: @"filters"
                                                           language: &language]);
    if (!source) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }

    CBLFilterBlock filter = [compiler compileFilterFunction: source language: language];
    if (!filter) {
        Warn(@"Filter %@ failed to compile", filterName);
        *outStatus = kCBLStatusCallbackError;
        return nil;
    }
    [self setFilterNamed: filterName asBlock: filter];
    return filter;
}


#pragma mark - ATTACHMENTS:


/** Returns a CBL_Attachment for an attachment in a stored revision. */
- (CBL_Attachment*) attachmentForRevision: (CBL_Revision*)rev
                                    named: (NSString*)filename
                                   status: (CBLStatus*)outStatus
{
    Assert(filename);
    NSDictionary* attachments = rev.attachments;
    if (!attachments) {
        attachments = [self attachmentsForDocID: rev.docID revID: rev.revID status: outStatus];
        if (!attachments) {
            *outStatus = kCBLStatusNotFound;
            return nil;
        }
    }
    return [self attachmentForDict: attachments[filename] named: filename status: outStatus];
}


/** Replaces or removes a single attachment in a document, by saving a new revision whose only
    change is the value of the attachment. */
- (CBL_Revision*) updateAttachment: (NSString*)filename
                              body: (CBL_BlobStoreWriter*)body
                              type: (NSString*)contentType
                          encoding: (CBLAttachmentEncoding)encoding
                           ofDocID: (NSString*)docID
                             revID: (CBL_RevID*)oldRevID
                            source: (NSURL*)source
                            status: (CBLStatus*)outStatus
                             error: (NSError**)outError
{
    *outStatus = kCBLStatusBadAttachment;
    if (filename.length == 0 || (body && !contentType) || (oldRevID && !docID) || (body && !docID)) {
        CBLStatusToOutNSError(*outStatus, outError);
        return nil;
    }

    CBL_MutableRevision* oldRev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                       revID: oldRevID
                                                                     deleted: NO];
    if (oldRevID) {
        // Load existing revision if this is a replacement:
        *outStatus = [self loadRevisionBody: oldRev];
        if (CBLStatusIsError(*outStatus)) {
            if (*outStatus == kCBLStatusNotFound
                && [self getDocumentWithID: docID revisionID: nil withBody: NO
                                    status: outStatus] != nil) {
                *outStatus = kCBLStatusConflict;   // if some other revision exists, it's a conflict
            }
            CBLStatusToOutNSError(*outStatus, outError);
            return nil;
        }
    } else {
        // If this creates a new doc, it needs a body:
        oldRev.body = [CBL_Body bodyWithProperties: @{}];
    }

    // Update the _attachments dictionary:
    NSMutableDictionary* attachments = [oldRev.attachments mutableCopy];
    if (!attachments)
        attachments = $mdict();
    if (body) {
        CBLBlobKey key = body.blobKey;
        NSString* digest = [CBLDatabase blobKeyToDigest: key];
        [self rememberAttachmentWriter: body forDigest: digest];
        NSString* encodingName = (encoding == kCBLAttachmentEncodingGZIP) ? @"gzip" : nil;
        attachments[filename] = $dict({@"digest", digest},
                                      {@"length", @(body.bytesWritten)},
                                      {@"follows", $true},
                                      {@"content_type", contentType},
                                      {@"encoding", encodingName});
    } else {
        if (oldRevID && !attachments[filename]) {
            *outStatus = kCBLStatusAttachmentNotFound;
            CBLStatusToOutNSError(*outStatus, outError);
            return nil;
        }
        [attachments removeObjectForKey: filename];
    }

    NSMutableDictionary* properties = [oldRev.properties mutableCopy];
    properties[@"_attachments"] = attachments;

    // Store a new revision with the updated _attachments:
    CBL_Revision* newRev = [self putDocID: docID
                               properties: properties
                           prevRevisionID: oldRevID allowConflict: NO
                                   source: source
                                   status: outStatus error: outError];
    if (!body && *outStatus == kCBLStatusCreated)
        *outStatus = kCBLStatusOK;

    return newRev;
}


@end
