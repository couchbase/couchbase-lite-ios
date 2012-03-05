//
//  TDC.h
//  TouchDB
//
//  Created by Jens Alfke on 3/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#ifndef _TDC_
#define _TDC_
#include <sys/types.h>
#include <stdbool.h>


/* Simple ANSI C API to TouchDB. */


/** C structure describing a MIME entity, used for requests and responses.
    This structure and the data it points to should be considered read-only.
    It should be created only by calling TDCMIMECreate, and freed only by calling TDCMIMEFree. */
typedef struct {
    unsigned headerCount;
    const char** headerNames;
    const char** headerValues;
    size_t contentLength;
    const void* content;
    void* _private;
} TDCMIME;


/** Allocates a TDCMIME structure on the heap, copying the headers and (optionally) the content.
    @param headerCount  The number of MIME headers.
    @param headerNames  An array of headerCount pointers to C strings, each a header name. (May be NULL if the headerCount is 0.)
    @param headerValues  An array of headerCount pointers to C strings, each a header value corresponding to the header name with the same index. (May be NULL if the headerCount is 0.)
    @param contentLength  The length of the content in bytes.
    @param content  The content itself (may be NULL if the conten length is 0.)
    @param copyContent  If true, the content will be copied into a new heap block owned by the TDCMIME structure. If false, the content pointer will be adopted by the TDCMIME and will be freed when the TDCMIME itself is freed (this implies the caller must have used malloc to allocate it.) If allocation fails, the content block is still valid and the caller is responsible for freeing it.
    @return  The allocated TDCMIME structure, or NULL if memory allocation failed.
 */
TDCMIME* TDCMIMECreate(unsigned headerCount,
                       const char** headerNames,
                       const char** headerValues,
                       size_t contentLength,
                       const void* content,
                       bool copyContent);


/** Frees a TDCMIME structure and all the data it points to.
    The structure *must* have been allocated by calling TDCMIMECreate.
    It is a safe no-op to pass NULL to this function.
    @param  The TDCMIME pointer to free, or NULL. */
void TDCMIMEFree(TDCMIME* mime);


/** Initializes the TDC API.
    This must be called once (and only once), before the first call to TDCSendRequest.
    @param dataDirectoryPath  The base directory in which TouchDB should store data files. This directory's parent directory must exist and be writeable. */
void TDCInitialize(const char* dataDirectoryPath);


/** Synchronously calls a TouchDB REST API method.
    This method is thread-safe: it may be called from any thread and from multiple threads simultaneously. This allows the application to implement asynchronous operations.
    @param method  The HTTP method -- "GET", "PUT", etc.
    @param url  The target URL. The scheme and host are ignored. We suggest using "touchdb:///".
    @param headersAndBody  The request headers and body. TouchDB takes ownership of this; the caller should NOT use, modify or free it after the call.
    @param outResponse  On return, may be filled in with a pointer to an allocated TDCMIME structure. Caller is responsible for freeing this via TDCMIMEFree. The value may be filled in as NULL if there is no meaningful data to return, as in some error conditions.
    @return  The HTTP status code of the response. */
int TDCSendRequest(const char* method,
                   const char* url,
                   TDCMIME* headersAndBody,
                   TDCMIME** outResponse);

#endif // _TDC_
