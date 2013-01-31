//
//  CBLC.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#ifndef _TDC_
#define _TDC_
#include <sys/types.h>
#include <stdbool.h>


/* Simple ANSI C API to CouchbaseLite. */


/** C structure describing a MIME entity, used for requests and responses.
    This structure and the data it points to should be considered read-only.
    It should be created only by calling CBLCMIMECreate, and freed only by calling CBLCMIMEFree. */
typedef struct {
    unsigned headerCount;
    const char** headerNames;
    const char** headerValues;
    size_t contentLength;
    const void* content;
    void* _private;
} CBLCMIME;


/** Allocates a CBLCMIME structure on the heap, copying the headers and (optionally) the content.
    @param headerCount  The number of MIME headers.
    @param headerNames  An array of headerCount pointers to C strings, each a header name. (May be NULL if the headerCount is 0.)
    @param headerValues  An array of headerCount pointers to C strings, each a header value corresponding to the header name with the same index. (May be NULL if the headerCount is 0.)
    @param contentLength  The length of the content in bytes.
    @param content  The content itself (may be NULL if the conten length is 0.)
    @param copyContent  If true, the content will be copied into a new heap block owned by the CBLCMIME structure. If false, the content pointer will be adopted by the CBLCMIME and will be freed when the CBLCMIME itself is freed (this implies the caller must have used malloc to allocate it.) If allocation fails, the content block is still valid and the caller is responsible for freeing it.
    @return  The allocated CBLCMIME structure, or NULL if memory allocation failed.
 */
CBLCMIME* CBLCMIMECreate(unsigned headerCount,
                       const char** headerNames,
                       const char** headerValues,
                       size_t contentLength,
                       const void* content,
                       bool copyContent);


/** Frees a CBLCMIME structure and all the data it points to.
    The structure *must* have been allocated by calling CBLCMIMECreate.
    It is a safe no-op to pass NULL to this function.
    @param  The CBLCMIME pointer to free, or NULL. */
void CBLCMIMEFree(CBLCMIME* mime);


/** Initializes the CBLC API.
    This must be called once (and only once), before the first call to CBLCSendRequest.
    @param dataDirectoryPath  The base directory in which CouchbaseLite should store data files. This directory's parent directory must exist and be writeable. */
void CBLCInitialize(const char* dataDirectoryPath);


/** Synchronously calls a CouchbaseLite REST API method.
    This method is thread-safe: it may be called from any thread and from multiple threads simultaneously. This allows the application to implement asynchronous operations.
    @param method  The HTTP method -- "GET", "PUT", etc.
    @param url  The target URL. The scheme and host are ignored. We suggest using "touchdb:///".
    @param headersAndBody  The request headers and body. CouchbaseLite takes ownership of this; the caller should NOT use, modify or free it after the call.
    @param outResponse  On return, may be filled in with a pointer to an allocated CBLCMIME structure. Caller is responsible for freeing this via CBLCMIMEFree. The value may be filled in as NULL if there is no meaningful data to return, as in some error conditions.
    @return  The HTTP status code of the response. */
int CBLCSendRequest(const char* method,
                   const char* url,
                   CBLCMIME* headersAndBody,
                   CBLCMIME** outResponse);

#endif // _TDC_
