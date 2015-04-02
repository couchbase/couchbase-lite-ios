//
//  Attachment_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/12/15.
//
//

#import "CBLTestCase.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+Replication.h"
#import "CBL_Storage.h"
#import "CBLDatabaseUpgrade.h"
#import "CBL_Attachment.h"
#import "CBL_Body.h"
#import "CBLRevision.h"
#import "CBLDatabaseChange.h"
#import "CBL_BlobStore.h"
#import "CBLBase64.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "GTMNSData+zlib.h"


@interface DatabaseAttachment_Tests : CBLTestCaseWithDB
@end


@implementation DatabaseAttachment_Tests
{
    BOOL _encrypt;
}


- (void)invokeTest {
    // Run each test method twice, once plain and once encrypted.
    _encrypt = NO;
    [super invokeTest];
    _encrypt = YES;
    [super invokeTest];
}

- (void) setUp {
    if (_encrypt)
        Log(@"++++ Now encrypting attachments");
    [super setUp];
    self.encryptedAttachmentStore = _encrypt;
}


- (void) test10_Attachments {
    RequireTestCase(CRUD);
    CBL_BlobStore* attachments = db.attachmentStore;

    AssertEq(attachments.count, 0u);
    AssertEqual(attachments.allKeys, @[]);
    
    // Add a revision and an attachment to it:
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSDictionary* props = @{@"foo": @1,
                            @"bar": $false,
                            @"_attachments": attachmentsDict(attach1, @"attach", @"text/plain", NO)};
    CBL_Revision* rev1;
    CBLStatus status;
    NSError* error;
    rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
            prevRevisionID: nil allowConflict: NO status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);

    CBL_Attachment* att = [db attachmentForRevision: rev1 named: @"attach" status: &status];
    Assert(att, @"Couldn't get attachment: status %d", status);
    AssertEqual(att.content, attach1);
    AssertEqual(att.contentType, @"text/plain");
    AssertEq(att->encoding, kCBLAttachmentEncodingNone);

    // Check the attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                           {@"length", @(27)},
                                           {@"stub", $true},
                                           {@"revpos", @1});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);
    
    // Check the attachment dict, with attachments included:
    [itemDict removeObjectForKey: @"stub"];
    itemDict[@"data"] = [CBLBase64 encode: attach1];
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                           withBody: YES
                             status: &status];
    CBL_MutableRevision* expandedRev = [gotRev1 mutableCopy];
    Assert([db expandAttachmentsIn: expandedRev
                         minRevPos: 0
                      allowFollows: NO
                            decode: YES
                            status: &status],
           @"expandAttachments failed: status %d", status);
    AssertEqual(expandedRev[@"_attachments"], attachmentDict);
    
    // Add a second revision that doesn't update the attachment:
    props = $dict({@"_id", rev1.docID},
                  {@"foo", @2},
                  {@"bazz", $false},
                  {@"_attachments", attachmentsStub(@"attach")});
    CBL_Revision* rev2 = [db putRevision: [CBL_MutableRevision revisionWithProperties:props]
                          prevRevisionID: rev1.revID allowConflict: NO
                                  status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);

    // Add a third revision of the same document:
    NSData* attach2 = [@"<html>And this is attach2</html>" dataUsingEncoding: NSUTF8StringEncoding];
    props = @{@"_id": rev2.docID,
              @"foo": @2,
              @"bazz": $false,
              @"_attachments": attachmentsDict(attach2, @"attach", @"text/html", NO)};
    CBL_Revision* rev3 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
                          prevRevisionID: rev2.revID allowConflict: NO
                                  status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);

    // Check the 2nd revision's attachment:
    att = [db attachmentForRevision: rev2 named: @"attach" status: &status];
    Assert(att, @"Couldn't get attachment: status %d", status);
    AssertEqual(att.content, attach1);
    AssertEqual(att.contentType, @"text/plain");
    AssertEq(att->encoding, kCBLAttachmentEncodingNone);

    expandedRev = [rev2 mutableCopy];
    Assert([db expandAttachmentsIn: expandedRev
                         minRevPos: 2
                      allowFollows: NO
                            decode: YES
                            status: &status],
           @"expandAttachments failed: status %d", status);
    AssertEqual(expandedRev[@"_attachments"], (@{@"attach": @{@"stub":@YES, @"revpos":@1}}));
    
    // Check the 3rd revision's attachment:
    att = [db attachmentForRevision: rev3 named: @"attach" status: &status];
    Assert(att, @"Couldn't get attachment: status %d", status);
    AssertEqual(att.content, attach2);
    AssertEqual(att.contentType, @"text/html");
    AssertEq(att->encoding, kCBLAttachmentEncodingNone);
    
    expandedRev = [rev3 mutableCopy];
    Assert([db expandAttachmentsIn: expandedRev
                         minRevPos: 2
                      allowFollows: NO
                            decode: YES
                            status: &status],
           @"expandAttachments failed: status %d", status);
    attachmentDict = @{@"attach": @{@"content_type": @"text/html",
                                    @"data":   @"PGh0bWw+QW5kIHRoaXMgaXMgYXR0YWNoMjwvaHRtbD4=",
                                    @"digest": @"sha1-s14XRTXlwvzYfjo1t1u0rjB+ZUA=",
                                    @"length": @32,
                                    @"revpos": @3}};
    AssertEqual(expandedRev[@"_attachments"], attachmentDict);

    // Examine the attachment store:
    AssertEq(attachments.count, 2u);
    NSSet* expected = [NSSet setWithObjects: [CBL_BlobStore keyDataForBlob: attach1],
                                             [CBL_BlobStore keyDataForBlob: attach2], nil];
    AssertEqual([NSSet setWithArray: attachments.allKeys], expected);
    
    Assert([db compact: NULL]);  // This clears the body of the first revision
    AssertEq(attachments.count, 1u);
    AssertEqual(attachments.allKeys, @[[CBL_BlobStore keyDataForBlob: attach2]]);
}


- (CBL_Revision*) putDoc: (NSString*)docID
          withAttachment: (NSString*) attachmentText
              compressed: (BOOL)compress
{
    NSData* attachmentData = [attachmentText dataUsingEncoding: NSUTF8StringEncoding];
    NSString* encoding = nil;
    NSNumber* length = nil;
    if (compress) {
        length = @(attachmentData.length);
        encoding = @"gzip";
        attachmentData = [NSData gtm_dataByGzippingData: attachmentData];
    }
    NSString* base64 = [CBLBase64 encode: attachmentData];
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"data", base64},
                                                           {@"encoding", encoding},
                                                           {@"length", length}
                                                           )});
    NSDictionary* props = $dict({@"_id", docID},
                                {@"foo", @1},
                                {@"bar", $false},
                                {@"_attachments", attachmentDict});
    CBLStatus status;
    NSError* error;
    CBL_Revision* rev = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
                         prevRevisionID: nil allowConflict: NO status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    return rev;
}


- (void) test11_PutAttachment {
    RequireTestCase(CBL_Database_CRUD);
    // Put a revision that includes an _attachments dict:
    CBL_Revision* rev1 = [self putDoc: nil withAttachment: @"This is the body of attach1" compressed: NO];
    AssertEqual(rev1[@"_attachments"], $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                                {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                                {@"length", @(27)},
                                                                {@"stub", $true},
                                                                {@"revpos", @1})}));

    // Examine the attachment store:
    AssertEq(db.attachmentStore.count, 1u);
    
    // Get the revision:
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    NSDictionary* attachmentDict = gotRev1[@"_attachments"];
    AssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                         {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                         {@"length", @(27)},
                                                         {@"stub", $true},
                                                         {@"revpos", @1})}));
    
    // Update the attachment directly:
    CBLStatus status;
    NSError* error;
    NSData* attachv2 = [@"Replaced body of attach" dataUsingEncoding: NSUTF8StringEncoding];
    [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                    type: @"application/foo"
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev1.docID revID: nil
                  status: &status
                   error: &error];
    AssertEq(status, kCBLStatusConflict);
    AssertEq(error.code, kCBLStatusConflict);
    error = nil;
    [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                    type: @"application/foo"
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev1.docID revID: @"1-deadbeef"
                  status: &status
                   error: &error];
    AssertEq(status, kCBLStatusConflict);
    AssertEq(error.code, kCBLStatusConflict);
    error = nil;
    CBL_Revision* rev2 = [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                                         type: @"application/foo"
                                     encoding: kCBLAttachmentEncodingNone
                                      ofDocID: rev1.docID revID: rev1.revID
                                       status: &status
                                        error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    AssertEqual(rev2.docID, rev1.docID);
    AssertEq(rev2.generation, 2u);

    // Get the updated revision:
    CBL_Revision* gotRev2 = [db getDocumentWithID: rev2.docID revisionID: rev2.revID];
    attachmentDict = gotRev2[@"_attachments"];
    AssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"application/foo"},
                                                         {@"digest", @"sha1-mbT3208HI3PZgbG4zYWbDW2HsPk="},
                                                         {@"length", @(23)},
                                                         {@"stub", $true},
                                                         {@"revpos", @2})}));

    CBL_Attachment* gotAttach = [db attachmentForRevision: gotRev2 named: @"attach" status: &status];
    Assert(gotAttach, @"Couldn't get attachment: status %d", status);
    AssertEqual(gotAttach.content, attachv2);

    // Delete the attachment:
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev2.docID revID: rev2.revID
                  status: &status
                   error: &error];
    AssertEq(status, kCBLStatusAttachmentNotFound);
    AssertEq(error.code, kCBLStatusNotFound); // The error code is mapped to the HTTP error code.
    error = nil;
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: @"nosuchdoc" revID: @"nosuchrev"
                  status: &status
                   error: &error];
    AssertEq(status, kCBLStatusNotFound);
    AssertEq(error.code, kCBLStatusNotFound);
    error = nil;
    CBL_Revision* rev3 = [db updateAttachment: @"attach" body: nil type: nil
                                     encoding: kCBLAttachmentEncodingNone
                                      ofDocID: rev2.docID revID: rev2.revID
                                       status: &status
                                        error: &error];
    AssertEq(status, kCBLStatusOK);
    AssertNil(error);
    AssertEqual(rev3.docID, rev2.docID);
    AssertEq(rev3.generation, 3u);

    // Get the updated revision:
    CBL_Revision* gotRev3 = [db getDocumentWithID: rev3.docID revisionID: rev3.revID];
    AssertNil((gotRev3.properties)[@"_attachments"]);
}


- (void)test11_PutEncodedAttachment {
    RequireTestCase(CBL_Database_PutAttachment);
    NSString* bodyString = @"This is the body of attach1";
    CBL_Revision* rev1 = [self putDoc: nil withAttachment: bodyString compressed: YES];
    AssertEqual(rev1[@"_attachments"], $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                                {@"digest", @"sha1-Wk8g89eb0Y+5DtvMKkf+/g90Mhc="},
                                                                {@"length", @(27)},
                                                                {@"encoded_length", @(45)},
                                                                {@"encoding", @"gzip"},
                                                                {@"stub", $true},
                                                                {@"revpos", @1})}));

    // Examine the attachment store:
    AssertEq(db.attachmentStore.count, 1u);

    // Get the revision:
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    NSDictionary* attachmentDict = gotRev1[@"_attachments"];
    AssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                         {@"digest", @"sha1-Wk8g89eb0Y+5DtvMKkf+/g90Mhc="},
                                                         {@"length", @(27)},
                                                         {@"encoded_length", @(45)},
                                                         {@"encoding", @"gzip"},
                                                         {@"stub", $true},
                                                         {@"revpos", @1})}));
    // Expand it without decoding:
    CBL_MutableRevision* expandedRev = [gotRev1 mutableCopy];
    CBLStatus status;
    Assert([db expandAttachmentsIn: expandedRev
                         minRevPos: 0
                      allowFollows: NO
                            decode: NO
                            status: &status],
           @"expandAttachments failed: status %d", status);

    NSString* encoded = [CBLBase64 encode: [NSData gtm_dataByGzippingData: [bodyString dataUsingEncoding: NSUTF8StringEncoding]]];
    AssertEqual(expandedRev[@"_attachments"],
                $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                        {@"digest", @"sha1-Wk8g89eb0Y+5DtvMKkf+/g90Mhc="},
                                        {@"length", @(27)},
                                        {@"encoded_length", @(45)},
                                        {@"encoding", @"gzip"},
                                        {@"data", encoded},
                                        {@"revpos", @1})}));

    // Expand it and decode:
    expandedRev = [gotRev1 mutableCopy];
    Assert([db expandAttachmentsIn: expandedRev
                         minRevPos: 0
                      allowFollows: NO
                            decode: YES
                            status: &status],
           @"expandAttachments failed: status %d", status);

    encoded = [CBLBase64 encode: [bodyString dataUsingEncoding: NSUTF8StringEncoding]];
    AssertEqual(expandedRev[@"_attachments"],
                $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                        {@"digest", @"sha1-Wk8g89eb0Y+5DtvMKkf+/g90Mhc="},
                                        {@"length", @(27)},
                                        {@"data", encoded},
                                        {@"revpos", @1})}));
}


// Test that updating an attachment via a PUT correctly updates its revpos.
- (void) test12_AttachmentRevPos {
    RequireTestCase(PutAttachment);

    // Put a revision that includes an _attachments dict:
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSString* base64 = [CBLBase64 encode: attach1];
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"data", base64})});
    NSDictionary* props = $dict({@"foo", @1},
                                {@"bar", $false},
                                {@"_attachments", attachmentDict});
    CBL_Revision* rev1;
    CBLStatus status;
    NSError* error;
    rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
            prevRevisionID: nil allowConflict: NO status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);

    AssertEqual((rev1[@"_attachments"])[@"attach"][@"revpos"], @1);

    // Update the attachment with another PUT:
    NSData* attach2 = [@"This WAS the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    base64 = [CBLBase64 encode: attach2];
    attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                             {@"data", base64})});
    props = $dict({@"_id", rev1.docID},
                  {@"foo", @2},
                  {@"bar", $true},
                  {@"_attachments", attachmentDict});
    CBL_Revision* rev2;
    rev2 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
            prevRevisionID: rev1.revID allowConflict: NO status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);

    // The punch line: Did the revpos get incremented to 2?
    AssertEqual((rev2[@"_attachments"])[@"attach"][@"revpos"], @2);
    [db _close];
}


- (void) test13_GarbageCollectAttachments {
    NSMutableArray* revs = $marray();
    for (int i=0; i<100; i++) {
        [revs addObject: [self putDoc: $sprintf(@"doc-%d", i)
                       withAttachment: $sprintf(@"Attachment #%d", i)
                           compressed: NO]];
    }
    for (int i=0; i<40; i++) {
        CBLStatus status;
        NSError* error;
        revs[i] = [db updateAttachment: @"attach" body: nil type: nil
                              encoding: kCBLAttachmentEncodingNone
                               ofDocID: [revs[i] docID] revID: [revs[i] revID]
                                status: &status error: &error];
    }

    NSError* error;
    Assert([db compact: &error], @"Compact failed: %@", error);
    AssertEq(db.attachmentStore.count, 60u);
    [db _close];
}


- (void) test14_FollowingAttachments {
    RequireTestCase(CBL_Database_PutAttachment);
    NSMutableString* attachStr = [@"boing " mutableCopy];
    while (attachStr.length < 8000)
        [attachStr appendString: attachStr];

    CBL_Revision* rev1 = [self putDoc: nil withAttachment: attachStr compressed: YES];
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];

    // If we force decoding, attachment will follow:
    CBL_MutableRevision* expandedRev = [gotRev1 mutableCopy];
    CBLStatus status;
    Assert([db expandAttachmentsIn: expandedRev
                         minRevPos: 0
                      allowFollows: YES
                            decode: YES
                            status: &status],
           @"expandAttachments failed: status %d", status);
    AssertEqualish(expandedRev[@"_attachments"],
                $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                        {@"digest", @"sha1-xow/vyonQ4VegLAEKRwLSFfVqNs="},
                                        {@"length", @(12288)},
                                        {@"revpos", @1},
                                        {@"follows", @YES})}));

    // If we allow attachment to stay encoded, it can be sent inline because it's small:
    expandedRev = [gotRev1 mutableCopy];
    Assert([db expandAttachmentsIn: expandedRev
                         minRevPos: 0
                      allowFollows: YES
                            decode: NO
                            status: &status],
           @"expandAttachments failed: status %d", status);
    NSData* zipped = [NSData gtm_dataByGzippingData: [attachStr dataUsingEncoding: NSUTF8StringEncoding]];
    Assert(zipped.length < 1024); // needs to be short for this test
    NSString* base64 = [CBLBase64 encode: zipped];
    AssertEqualish(expandedRev[@"_attachments"],
                $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                        {@"digest", @"sha1-xow/vyonQ4VegLAEKRwLSFfVqNs="},
                                        {@"length", @(12288)},
                                        {@"encoding", @"gzip"},
                                        {@"encoded_length", @61},
                                        {@"data", base64},
                                        {@"revpos", @1})}));
}


static NSDictionary* attachmentsDict(NSData* data, NSString* name, NSString* type, BOOL gzipped) {
    if (gzipped)
        data = [NSData gtm_dataByGzippingData: data];
    NSMutableDictionary* att = $mdict({@"content_type", type}, {@"data", data});
    if (gzipped)
        att[@"encoding"] = @"gzip";
    return $dict({name, att});
}

static NSDictionary* attachmentsStub(NSString* name) {
    return @{name: @{@"stub": $true}};
}


static CBL_BlobStoreWriter* blobForData(CBLDatabase* db, NSData* data) {
    CBL_BlobStoreWriter* blob = db.attachmentWriter;
    [blob appendData: data];
    [blob finish];
    return blob;
}


@end
