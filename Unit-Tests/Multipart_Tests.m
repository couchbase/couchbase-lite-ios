//
//  Multipart_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/23/14.
//
//

#import "CBLTestCase.h"
#import "CBLMultipartDownloader.h"
#import "CBLMultipartDocumentReader.h"
#import "CBLMultipartWriter.h"
#import "CBLInternal.h"
#import "CBLRemoteSession.h"
#import "CBL_BlobStore.h"
#import "CBL_BlobStoreWriter.h"
#import "CBLGZip.h"


// Another hardcoded DB that needs to exist on the remote test server.
#define kAttachTestDBName @"attach_test"


@interface Multipart_Tests : CBLTestCaseWithDB
@end


@implementation Multipart_Tests


- (void) test_CBLMultipartWriter {
    NSString* expectedOutput = @"\r\n--BOUNDARY\r\nContent-Length: 16\r\n\r\n<part the first>\r\n--BOUNDARY\r\nContent-Length: 10\r\nContent-Type: something\r\n\r\n<2nd part>\r\n--BOUNDARY--";
    RequireTestCase(CBLMultiStreamWriter);
    for (unsigned bufSize = 1; bufSize < expectedOutput.length+1; ++bufSize) {
        CBLMultipartWriter* mp = [[CBLMultipartWriter alloc] initWithContentType: @"foo/bar"
                                                                        boundary: @"BOUNDARY"];
        AssertEqual(mp.contentType, @"foo/bar; boundary=\"BOUNDARY\"");
        AssertEqual(mp.boundary, @"BOUNDARY");
        [mp addData: [@"<part the first>" dataUsingEncoding: NSUTF8StringEncoding]];
        [mp setNextPartsHeaders: $dict({@"Content-Type", @"something"})];
        [mp addData: [@"<2nd part>" dataUsingEncoding: NSUTF8StringEncoding]];
        AssertEq((NSUInteger)mp.length, expectedOutput.length);

        NSData* output = [mp allOutput];
        AssertEqual(output.my_UTF8ToString, expectedOutput);
        [mp close];
    }
}


- (void) test_CBLMultipartWriterGZipped {
    RequireTestCase(CBLMultipartWriter);
    CBLMultipartWriter* mp = [[CBLMultipartWriter alloc] initWithContentType: @"foo/bar"
                                                                    boundary: @"BOUNDARY"];
    NSMutableData* data1 = [NSMutableData dataWithLength: 100];
    memset(data1.mutableBytes, '*', data1.length);
    [mp setNextPartsHeaders: @{@"Content-Type": @"star-bellies"}];
    [mp addGZippedData: data1];
    NSData* output = [mp allOutput];
    AssertEqual(output, [self contentsOfTestFile: @"MultipartStars.mime"]);
}


- (void) test_CBLMultipartDownloader {
    RequireTestCase(CBL_BlobStore);
    RequireTestCase(CBLMultipartReader_Simple);
    RequireTestCase(CBLMultipartReader_Types);

    NSString* urlStr = [self remoteTestDBURL: kAttachTestDBName].absoluteString;
    if (!urlStr)
        return;
    urlStr = [urlStr stringByAppendingString: @"/oneBigAttachment?revs=true&attachments=true"];
    NSURL* url = [NSURL URLWithString: urlStr];
    __block BOOL done = NO;
    CBLMultipartDownloader* dl;
    dl = [[CBLMultipartDownloader alloc] initWithURL: url
                                        database: db
                                    onCompletion: ^(id result, NSError * error)
      {
          AssertNil(error);
          CBLMultipartDownloader* request = result;
          Log(@"Got document: %@", request.document);
          NSDictionary* attachments = (request.document).cbl_attachments;
          Assert(attachments.count >= 1);
          AssertEq(db.attachmentStore.count, 0u);
          for (NSDictionary* attachment in attachments.allValues) {
              CBL_BlobStoreWriter* writer = [db attachmentWriterForAttachment: attachment];
              Assert(writer);
              Assert([writer install]);
              NSData* blob = [db.attachmentStore blobForKey: writer.blobKey];
              Log(@"Found %u bytes of data for attachment %@", (unsigned)blob.length, attachment);
              NSNumber* lengthObj = attachment[@"encoded_length"] ?: attachment[@"length"];
              AssertEq(blob.length, [lengthObj unsignedLongLongValue]);
              AssertEq(writer.bytesWritten, blob.length);
          }
          AssertEq(db.attachmentStore.count, attachments.count);
          done = YES;
      }];
    dl.debugAlwaysTrust = YES;
    CBLRemoteSession* session = [[CBLRemoteSession alloc] initWithDelegate: nil];
    [session startRequest: dl];

    while (!done)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
}


- (void) test_CBLMultipartDocumentReader {
    NSData* mime = [self contentsOfTestFile: @"Multipart1.mime"];
    NSDictionary* headers = @{@"Content-Type": @"multipart/mixed; boundary=\"BOUNDARY\""};
    CBLStatus status;
    NSDictionary* dict = [CBLMultipartDocumentReader readData: mime headers: headers toDatabase: db status: &status];
    Assert(!CBLStatusIsError(status));
    AssertEqual(dict, (@{@"_id": @"THX-1138",
                         @"_rev": @"1-foobar",
                         @"_attachments": @{
                                 @"mary.txt": @{@"type": @"text/doggerel", @"length": @52,
                                                @"follows": @YES,
                                                @"digest": @"md5-1WWSGl9mJACzGjclAafpfQ=="}
                                 }}));
    NSDictionary* attachment = (dict[@"_attachments"])[@"mary.txt"];
    CBL_BlobStoreWriter* writer = [db attachmentWriterForAttachment: attachment];
    Assert(writer);
    AssertEq(writer.bytesWritten, 52u);

    mime = [self contentsOfTestFile: @"MultipartBinary.mime"];
    headers = @{@"Content-Type": @"multipart/mixed; boundary=\"dc0bf3cdc9a6c6e4c46fe2a361c8c5d7\""};
    dict = [CBLMultipartDocumentReader readData: mime headers: headers toDatabase: db status: &status];
    Assert(!CBLStatusIsError(status));
    AssertEqual(dict, (@{@"_id": @"038c536dc29ff0f4127705879700062c",
                          @"_rev":@"3-e715bcf1865f8283ab1f0ba76e7a92ba",
                          @"_attachments":@{
                                  @"want3.jpg":@{
                                          @"content_type":@"image/jpeg",
                                          @"revpos":@3,
                                          @"digest":@"md5-/rAceS7EjR+CDHdYp8zKOg==",
                                          @"length":@24758,
                                          @"follows":@YES},
                                  @"Toad.gif":@{
                                          @"content_type":@"image/gif",
                                          @"revpos":@2,
                                          @"digest":@"md5-6UpXIDR/olzgZrDhsMe7Sw==",
                                          @"length":@6566,
                                          @"follows":@YES}}}));
    attachment = (dict[@"_attachments"])[@"Toad.gif"];
    writer = [db attachmentWriterForAttachment: attachment];
    Assert(writer);
    AssertEq(writer.bytesWritten, 6566u);
    attachment = (dict[@"_attachments"])[@"want3.jpg"];
    writer = [db attachmentWriterForAttachment: attachment];
    Assert(writer);
    AssertEq(writer.bytesWritten, 24758u);

    // Read data that's equivalent to the last one except the JSON is gzipped:
    mime = [self contentsOfTestFile: @"MultipartBinary.mime"];
    headers = @{@"Content-Type": @"multipart/mixed; boundary=\"dc0bf3cdc9a6c6e4c46fe2a361c8c5d7\""};
    NSDictionary* unzippedDict = [CBLMultipartDocumentReader readData: mime headers: headers toDatabase: db status: &status];
    AssertEqual(unzippedDict, dict);
}


@end


#pragma mark - MULTISTREAM WRITER TESTS


#define kExpectedOutputString @"<part the first, let us make it a bit longer for greater interest><2nd part, again unnecessarily prolonged for testing purposes beyond any reasonable length...>"

@interface MultiStreamWriter_Tests : CBLTestCase <NSStreamDelegate>
{
    NSInputStream* _stream;
    NSMutableData* _output;
    BOOL _finished;
}
@end


@implementation MultiStreamWriter_Tests


- (CBLMultiStreamWriter*) createWriterWithBufferSize: (unsigned)bufSize {
    CBLMultiStreamWriter* stream = [[CBLMultiStreamWriter alloc] initWithBufferSize: bufSize];
    [stream addData: [@"<part the first, let us make it a bit longer for greater interest>" dataUsingEncoding: NSUTF8StringEncoding]];
    [stream addData: [@"<2nd part, again unnecessarily prolonged for testing purposes beyond any reasonable length...>" dataUsingEncoding: NSUTF8StringEncoding]];
    AssertEq(stream.length, (SInt64)kExpectedOutputString.length);
    return stream;
}


- (void) test_CBLMultiStreamWriter_Sync {
    for (unsigned bufSize = 1; bufSize < 128; ++bufSize) {
        Log(@"Buffer size = %u", bufSize);
        CBLMultiStreamWriter* mp = [self createWriterWithBufferSize: bufSize];
        NSData* outputBytes = [mp allOutput];
        AssertEqual(outputBytes.my_UTF8ToString, kExpectedOutputString);
        // Run it a second time to make sure re-opening works:
        outputBytes = [mp allOutput];
        AssertEqual(outputBytes.my_UTF8ToString, kExpectedOutputString);
    }
}


- (void) setStream: (NSInputStream*)stream {
    _stream = stream;
    _output = [[NSMutableData alloc] init];
    stream.delegate = self;
}


- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    AssertEq(stream, _stream);
    switch (event) {
        case NSStreamEventOpenCompleted:
            Log(@"NSStreamEventOpenCompleted");
            break;
        case NSStreamEventHasBytesAvailable: {
            Log(@"NSStreamEventHasBytesAvailable");
            uint8_t buffer[10];
            NSInteger length = [_stream read: buffer maxLength: sizeof(buffer)];
            Log(@"    read %d bytes", (int)length);
            //Assert(length > 0);
            [_output appendBytes: buffer length: length];
            break;
        }
        case NSStreamEventEndEncountered:
            Log(@"NSStreamEventEndEncountered");
            _finished = YES;
            break;
        default:
            Assert(NO, @"Unexpected stream event %d", (int)event);
    }
}


- (void) test_CBLMultiStreamWriter_Async {
    CBLMultiStreamWriter* writer = [self createWriterWithBufferSize: 16];
    NSInputStream* input = [writer openForInputStream];
    Assert(input);
    [self setStream: input];
    NSRunLoop* rl = [NSRunLoop currentRunLoop];
    [input scheduleInRunLoop: rl forMode: NSDefaultRunLoopMode];
    Log(@"Opening stream");
    [input open];
    
    while (!_finished) {
        Log(@"...waiting for stream...");
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
    }

    [input removeFromRunLoop: rl forMode: NSDefaultRunLoopMode];
    Log(@"Closing stream");
    [input close];
    [writer close];
    AssertEqual(_output.my_UTF8ToString, @"<part the first, let us make it a bit longer for greater interest><2nd part, again unnecessarily prolonged for testing purposes beyond any reasonable length...>");
}

@end



#pragma mark - MULTIPART READER TESTS


@interface MultipartReader_Tests : CBLTestCase <CBLMultipartReaderDelegate>
@end


@implementation MultipartReader_Tests
{
    NSMutableData* _currentPartData;
    NSMutableArray* _partList, *_headersList;
}


- (void) setUp {
    [super setUp];
    [self reset];
}

- (void) reset {
    _currentPartData = nil;
    _partList = _headersList = nil;
}

- (BOOL) startedPart: (NSDictionary*)headers {
    Assert(!_currentPartData);
    _currentPartData = [[NSMutableData alloc] init];
    if (!_partList)
        _partList = [[NSMutableArray alloc] init];
    [_partList addObject: _currentPartData];
    if (!_headersList)
        _headersList = [[NSMutableArray alloc] init];
    [_headersList addObject: headers];
    return YES;
}

- (BOOL) appendToPart: (NSData*)data {
    Assert(_currentPartData);
    [_currentPartData appendData: data];
    return YES;
}

- (BOOL) finishedPart {
    Assert(_currentPartData);
    _currentPartData = nil;
    return YES;
}


- (void) test_Types {
    CBLMultipartReader* reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=\"BOUNDARY\"" delegate: nil];
    AssertEqual(reader.boundary, [@"\r\n--BOUNDARY" dataUsingEncoding: NSUTF8StringEncoding]);

    reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=BOUNDARY" delegate: nil];
    AssertEqual(reader.boundary, [@"\r\n--BOUNDARY" dataUsingEncoding: NSUTF8StringEncoding]);
    
    reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=\"BOUNDARY" delegate: nil];
    AssertNil(reader);

    reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related;boundary=X" delegate: nil];
    AssertEqual(reader.boundary, [@"\r\n--X" dataUsingEncoding: NSUTF8StringEncoding]);
}


- (void) test_Simple {
    RequireTestCase(CBLMultipartReader_Types);
    NSData* mime = [@"--BOUNDARY\r\nFoo: Bar\r\n Header : Val ue \r\n\r\npart the first\r\n--BOUNDARY  \r\n\r\n2nd part\r\n--BOUNDARY--"
                            dataUsingEncoding: NSUTF8StringEncoding];
        
    NSArray* expectedParts = @[[@"part the first" dataUsingEncoding: NSUTF8StringEncoding],
                                    [@"2nd part" dataUsingEncoding: NSUTF8StringEncoding]];
    NSArray* expectedHeaders = @[$dict({@"Foo", @"Bar"},
                                            {@"Header", @"Val ue"}),
                                      $dict()];

    for (NSUInteger chunkSize = 1; chunkSize <= mime.length; ++chunkSize) {
        Log(@"--- chunkSize = %u", (unsigned)chunkSize);
        [self reset];
        CBLMultipartReader* reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=\"BOUNDARY\"" delegate: self];
        Assert(!reader.finished);
        
        NSRange r = {0, 0};
        do {
            Assert(r.location < mime.length, @"Parser didn't stop at end");
            r.length = MIN(chunkSize, mime.length - r.location);
            [reader appendData: [mime subdataWithRange: r]];
            Assert(!reader.error, @"Reader got a parse error: %@", reader.error);
            r.location += chunkSize;
        } while (!reader.finished);
        AssertEqual(_partList, expectedParts);
        AssertEqual(_headersList, expectedHeaders);
    }
}

- (void) test_GZipped {
    NSData* mime = [self contentsOfTestFile: @"MultipartStars.mime"];
    CBLMultipartReader* reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=\"BOUNDARY\"" delegate: self];
    [reader appendData: mime];
    Assert(reader.finished);

    AssertEqual(_headersList, (@[@{@"Content-Encoding": @"gzip",
                                   @"Content-Length": @"24",
                                   @"Content-Type": @"star-bellies"}]));

    NSData* stars = [CBLGZip dataByDecompressingData: _partList[0]];
    AssertEq(stars.length, 100u);
    for (int i=0; i<100; i++)
        AssertEq(((char*)stars.bytes)[i], '*');
}


@end
