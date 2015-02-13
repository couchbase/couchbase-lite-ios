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
    rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
            prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

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
                            options: kCBLIncludeAttachments
                             status: &status];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);
    
    // Add a second revision that doesn't update the attachment:
    props = $dict({@"_id", rev1.docID},
                  {@"foo", @2},
                  {@"bazz", $false},
                  {@"_attachments", attachmentsStub(@"attach")});
    CBL_Revision* rev2 = [db putRevision: [CBL_MutableRevision revisionWithProperties:props]
                          prevRevisionID: rev1.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

    // Add a third revision of the same document:
    NSData* attach2 = [@"<html>And this is attach2</html>" dataUsingEncoding: NSUTF8StringEncoding];
    props = @{@"_id": rev2.docID,
              @"foo": @2,
              @"bazz": $false,
              @"_attachments": attachmentsDict(attach2, @"attach", @"text/html", NO)};
    CBL_Revision* rev3 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
                          prevRevisionID: rev2.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

    // Check the 2nd revision's attachment:
    att = [db attachmentForRevision: rev2 named: @"attach" status: &status];
    Assert(att, @"Couldn't get attachment: status %d", status);
    AssertEqual(att.content, attach1);
    AssertEqual(att.contentType, @"text/plain");
    AssertEq(att->encoding, kCBLAttachmentEncodingNone);
    
    // Check the 3rd revision's attachment:
    att = [db attachmentForRevision: rev3 named: @"attach" status: &status];
    Assert(att, @"Couldn't get attachment: status %d", status);
    AssertEqual(att.content, attach2);
    AssertEqual(att.contentType, @"text/html");
    AssertEq(att->encoding, kCBLAttachmentEncodingNone);
    
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
    CBL_Revision* rev = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
                         prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
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
    NSData* attachv2 = [@"Replaced body of attach" dataUsingEncoding: NSUTF8StringEncoding];
    [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                    type: @"application/foo"
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev1.docID revID: nil
                  status: &status];
    AssertEq(status, kCBLStatusConflict);
    [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                    type: @"application/foo"
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev1.docID revID: @"1-deadbeef"
                  status: &status];
    AssertEq(status, kCBLStatusConflict);
    CBL_Revision* rev2 = [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                                        type: @"application/foo"
                                   encoding: kCBLAttachmentEncodingNone
                                    ofDocID: rev1.docID revID: rev1.revID
                                     status: &status];
    AssertEq(status, kCBLStatusCreated);
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
                  status: &status];
    AssertEq(status, kCBLStatusAttachmentNotFound);
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: @"nosuchdoc" revID: @"nosuchrev"
                  status: &status];
    AssertEq(status, kCBLStatusNotFound);
    CBL_Revision* rev3 = [db updateAttachment: @"attach" body: nil type: nil
                                     encoding: kCBLAttachmentEncodingNone
                                      ofDocID: rev2.docID revID: rev2.revID
                                       status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rev3.docID, rev2.docID);
    AssertEq(rev3.generation, 3u);

    // Get the updated revision:
    CBL_Revision* gotRev3 = [db getDocumentWithID: rev3.docID revisionID: rev3.revID];
    AssertNil((gotRev3.properties)[@"_attachments"]);
}


- (void)test11_PutEncodedAttachment {
    RequireTestCase(CBL_Database_PutAttachment);
    CBL_Revision* rev1 = [self putDoc: nil withAttachment: @"This is the body of attach1" compressed: YES];
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
    rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
            prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

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
            prevRevisionID: rev1.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

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
        revs[i] = [db updateAttachment: @"attach" body: nil type: nil
                              encoding: kCBLAttachmentEncodingNone
                               ofDocID: [revs[i] docID] revID: [revs[i] revID]
                                status: &status];
    }

    NSError* error;
    Assert([db compact: &error], @"Compact failed: %@", error);
    AssertEq(db.attachmentStore.count, 60u);
    [db _close];
}


#if 0
- (void) test14_EncodedAttachment {
    RequireTestCase(CBL_Database_CRUD);
    // Start with a fresh database in /tmp:
    CBLDatabase* db = createDB();

    // Add a revision and an attachment to it:
    CBL_Revision* rev1;
    CBLStatus status;
    rev1 = [db putRevision: [CBL_Revision revisionWithProperties:$dict({@"foo", @1},
                                                                     {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
    
    NSData* attach1 = [@"Encoded! Encoded!Encoded! Encoded! Encoded! Encoded! Encoded! Encoded!"
                            dataUsingEncoding: NSUTF8StringEncoding];
    NSData* encoded = [NSData gtm_dataByGzippingData: attach1];
    insertAttachment(self, encoded,
                     rev1.sequence,
                     @"attach", @"text/plain",
                     kCBLAttachmentEncodingGZIP,
                     attach1.length,
                     encoded.length,
                     rev1.generation);
    
    // Read the attachment without decoding it:
    NSString* type;
    CBLAttachmentEncoding encoding;
    AssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: &encoding status: &status], encoded);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(type, @"text/plain");
    AssertEq(encoding, kCBLAttachmentEncodingGZIP);
    
    // Read the attachment, decoding it:
    AssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: NULL status: &status], attach1);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(type, @"text/plain");
    
    // Check the stub attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-fhfNE/UKv/wgwDNPtNvG5DN/5Bg="},
                                           {@"length", @(70)},
                                           {@"encoding", @"gzip"},
                                           {@"encoded_length", @(37)},
                                           {@"stub", $true},
                                           {@"revpos", @1});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    AssertEqual([db getAttachmentDictForSequence: rev1.sequence options: 0], attachmentDict);
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);

    // Check the attachment dict with encoded data:
    itemDict[@"data"] = [CBLBase64 encode: encoded];
    [itemDict removeObjectForKey: @"stub"];
    AssertEqual([db getAttachmentDictForSequence: rev1.sequence
                                          options: kCBLIncludeAttachments | kCBLLeaveAttachmentsEncoded],
                 attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kCBLIncludeAttachments | kCBLLeaveAttachmentsEncoded
                             status: &status];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);

    // Check the attachment dict with data:
    itemDict[@"data"] = [CBLBase64 encode: attach1];
    [itemDict removeObjectForKey: @"encoding"];
    [itemDict removeObjectForKey: @"encoded_length"];
    AssertEqual([db getAttachmentDictForSequence: rev1.sequence options: kCBLIncludeAttachments], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kCBLIncludeAttachments
                             status: &status];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);
}
#endif


- (void) test15_StubOutAttachmentsBeforeRevPos {
    NSDictionary* hello = $dict({@"revpos", @1}, {@"follows", $true});
    NSDictionary* goodbye = $dict({@"revpos", @2}, {@"data", @"squeeee"});
    NSDictionary* attachments = $dict({@"hello", hello}, {@"goodbye", goodbye});
    
    CBL_MutableRevision* rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 3 attachmentsFollow: NO];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"stub", $true})})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 2 attachmentsFollow: NO];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", goodbye})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 1 attachmentsFollow: NO];
    AssertEqual(rev.properties, $dict({@"_attachments", attachments}));
    
    // Now test the "follows" mode:
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 3 attachmentsFollow: YES];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"stub", $true})})}));

    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 2 attachmentsFollow: YES];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"follows", $true})})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 1 attachmentsFollow: YES];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"follows", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"follows", $true})})}));
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
