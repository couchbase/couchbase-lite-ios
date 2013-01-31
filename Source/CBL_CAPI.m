//
//  CBLC.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBLC.h"
#import "CBL_Body.h"
#import "CBLRouter.h"
#import "CBL_Server.h"
#import "Test.h"
#import <string.h>


static NSLock* sLock;
static NSString* sServerDir;
static CBL_Server* sServer;


static NSString* CToNSString(const char* str) {
    return [[[NSString alloc] initWithCString: str encoding: NSUTF8StringEncoding] autorelease];
}


static void FreeStringList(unsigned count, const char** stringList) {
    if (!stringList)
        return;
    for (unsigned i = 0; i < count; ++i)
        free((char*)stringList[i]);
    free(stringList);
}


static const char** CopyStringList(unsigned count, const char** stringList) {
    if (count == 0)
        return NULL;
    const char** output = (const char**) malloc(count * sizeof(const char*));
    if (!output)
        return NULL;
    for (unsigned i = 0; i < count; ++i) {
        output[i] = strdup(stringList[i]);
        if (!output[i]) {
            FreeStringList(i, output);
            return NULL;
        }
    }
    return output;
}


CBLCMIME* CBLCMIMECreate(unsigned headerCount,
                       const char** headerNames,
                       const char** headerValues,
                       size_t contentLength,
                       const void* content,
                       bool copyContent)
{
    CBLCMIME* mime = calloc(sizeof(CBLCMIME), 1);  // initialized to all 0 for safety
    if (!mime)
        goto fail;
    if (headerCount > 0) {
        mime->headerCount = headerCount;
        mime->headerNames = CopyStringList(headerCount, headerNames);
        mime->headerValues = CopyStringList(headerCount, headerValues);
        if (!mime->headerNames || !mime->headerValues)
            goto fail;
    }
    if (contentLength > 0) {
        mime->contentLength = contentLength;
        if (copyContent) {
            mime->content = malloc(contentLength);
            if (!mime->content)
                goto fail;
            memcpy((void*)mime->content, content, contentLength);
        } else {
            mime->content = content;
        }
    }
    return mime;
    
fail:
    CBLCMIMEFree(mime);
    return NULL;
}


// Creates a CBLCMIME whose body comes from an NSData object, without copying the body.
static CBLCMIME* CBLCMIMECreateWithNSData(unsigned headerCount,
                                        const char** headerNames,
                                        const char** headerValues,
                                        NSData* content)
{
    CBLCMIME* mime = CBLCMIMECreate(headerCount, headerNames, headerValues,
                                  content.length, content.bytes, NO);
    if (mime)
        mime->_private = [content retain];
    return mime;
}


void CBLCMIMEFree(CBLCMIME* mime) {
    if (!mime)
        return;
    FreeStringList(mime->headerCount, mime->headerNames);
    FreeStringList(mime->headerCount, mime->headerValues);
    if (mime->_private)  // _private field points to NSData that owns the content ptr
        [(NSData*)mime->_private release];
    else
        free((void*)mime->content);
    free(mime);
}


void CBLCInitialize(const char* dataDirectoryPath) {
    assert(!sServerDir);
    sServerDir = [CToNSString(dataDirectoryPath) retain];
    assert(sServerDir);
    sLock = [[NSLock alloc] init];
}


// Creates an NSURLRequest from a method, URL, headers and body.
static NSURLRequest* CreateRequest(NSString* method, 
                                   NSString* urlStr,
                                   CBLCMIME* headersAndBody)
{
    NSURL* url = urlStr ? [NSURL URLWithString: urlStr] : nil;
    if (!url) {
        Warn(@"Invalid URL <%@>", urlStr);
        return nil;
    }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    if (headersAndBody) {
        for (unsigned i = 0; i < headersAndBody->headerCount; ++i) {
            NSString* header = CToNSString(headersAndBody->headerNames[i]);
            NSString* value = CToNSString(headersAndBody->headerValues[i]);
            if (!header || !value) {
                Warn(@"Invalid request headers");
                return nil;
            }
            [request setValue: value forHTTPHeaderField: header];
        }
        
        if (headersAndBody->content) {
            request.HTTPBody = [NSData dataWithBytesNoCopy: (void*)headersAndBody->content
                                                    length: headersAndBody->contentLength];
            headersAndBody->content = NULL;  // prevent double free
        }
    }
    return request;
}


// Actually runs the pre-parsed request through a CBLRouter. This method is thread-safe.
static CBLResponse* RunRequest(NSURLRequest* request) {
    assert(sLock);
    [sLock lock];
    @try {
        // Create CBL_Server on first call:
        if (!sServer) {
            assert(sServerDir);
            NSError* error;
            sServer = [[CBL_Server alloc] initWithDirectory: sServerDir error: &error];
            if (!sServer) {
                Warn(@"Unable to create CouchbaseLite server: %@", error);
                return nil;
            }
        }
        
        CBLRouter* router = [[[CBLRouter alloc] initWithServer: sServer
                                                     request: request] autorelease];
        __block bool finished = false;
        router.onFinished = ^{finished = true;};
        [router start];
        while (!finished) {
            if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                          beforeDate: [NSDate dateWithTimeIntervalSinceNow: 5]])
                break;
        }
        
        return finished ? router.response : nil;
    } @catch (NSException *x) {
        Warn(@"CBLCSendRequest caught %@", x);
        return nil;
    } @finally {
        [sLock unlock];
    }
}


// Converts a CBLResponse object to a CBLCMIME structure.
static CBLCMIME* CreateMIMEFromTDResponse(CBLResponse* response) {
    NSDictionary* headers = response.headers;
    NSArray* headerNames = headers.allKeys;
    unsigned headerCount = headers.count;
    const char* cHeaderNames[headerCount], *cHeaderValues[headerCount];
    for (unsigned i = 0; i < headerCount; ++i) {
        NSString* name = [headerNames objectAtIndex: i];
        cHeaderNames[i] = [name UTF8String];
        cHeaderValues[i] = [[headers objectForKey: name] UTF8String];
    }
    return CBLCMIMECreateWithNSData(headerCount, cHeaderNames, cHeaderValues, response.body.asJSON);
}


int CBLCSendRequest(const char* method,
                   const char* url,
                   CBLCMIME* headersAndBody,
                   CBLCMIME** outResponse)
{
    @autoreleasepool {
        *outResponse = NULL;
        
        NSURLRequest* request = CreateRequest(CToNSString(method),
                                              CToNSString(url),
                                              headersAndBody);
        CBLCMIMEFree(headersAndBody);
        if (!request)
            return 400;
        
        CBLResponse* response = RunRequest(request);
        if (!response)
            return 500;
        *outResponse = CreateMIMEFromTDResponse(response);
        return response.status;
    }
}




TestCase(CBLCSendRequest) {
    CBLCInitialize("/tmp/CBLCTest");
    
    CBLCMIME* response;
    int status = CBLCSendRequest("GET", "touchdb:///", NULL, &response);
    CAssertEq(status, 200);
    
    NSString* body = [[[NSString alloc] initWithData: [NSData dataWithBytes: response->content
                                                                     length: response->contentLength]
                                            encoding: NSUTF8StringEncoding] autorelease];
    Log(@"Response body = '%@'", body);
    CAssert([body rangeOfString: @"CouchbaseLite"].length > 0);
    bool gotContentType=false, gotServer=false;
    for (unsigned i = 0; i < response->headerCount; ++i) {
        Log(@"Header #%d: %s = %s", i+1, response->headerNames[i], response->headerValues[i]);
        if (strcmp(response->headerNames[i], "Content-Type") == 0) {
            gotContentType = true;
            CAssert(strcmp(response->headerValues[i], "application/json") == 0);
        } else if (strcmp(response->headerNames[i], "Server") == 0) {
            gotServer = true;
            CAssert(strncmp(response->headerValues[i], "CouchbaseLite", 7) == 0);
        }
    }
    CAssert(gotContentType);
    CAssert(gotServer);
    CBLCMIMEFree(response);
}
