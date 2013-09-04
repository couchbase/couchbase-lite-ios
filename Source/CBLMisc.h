//
//  CBLMisc.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBL_Revision.h"

NSString* CBLVersionString( void );

extern NSString* const CBLHTTPErrorDomain;

NSString* CBLCreateUUID( void );

NSData* CBLSHA1Digest( NSData* input ) __attribute__((nonnull));
NSData* CBLSHA256Digest( NSData* input ) __attribute__((nonnull));

NSString* CBLHexSHA1Digest( NSData* input ) __attribute__((nonnull));

NSData* CBLHMACSHA1(NSData* key, NSData* data) __attribute__((nonnull));
NSData* CBLHMACSHA256(NSData* key, NSData* data) __attribute__((nonnull));

/** Generates a hex dump of a sequence of bytes.
    The result is lowercase. This is important for CouchDB compatibility. */
NSString* CBLHexFromBytes( const void* bytes, size_t length) __attribute__((nonnull));

NSComparisonResult CBLSequenceCompare( SequenceNumber a, SequenceNumber b);

/** Escapes a document or revision ID for use in a URL.
    This does the usual %-escaping, but makes sure that '/' is escaped in case the ID appears in the path portion of the URL, and that '&' is escaped in case the ID appears in a query value. */
NSString* CBLEscapeID( NSString* param ) __attribute__((nonnull));

/** Escapes a string to be used as the value of a query parameter in a URL.
    This does the usual %-escaping, but makes sure that '&' is also escaped. */
NSString* CBLEscapeURLParam( NSString* param ) __attribute__((nonnull));

/** Wraps a string in double-quotes and prepends backslashes to any existing double-quote or backslash characters in it. */
NSString* CBLQuoteString( NSString* param );

/** Undoes effect of CBLQuoteString, i.e. removes backslash escapes and any surrounding double-quotes.
    If the string has no surrounding double-quotes it will be returned as-is. */
NSString* CBLUnquoteString( NSString* param );

/** Abbreviates a string to 10 characters or less by replacing its middle with "..". */
NSString* CBLAbbreviate( NSString* str );

/** Returns YES if this error appears to be due to the computer being offline or the remote host being unreachable. */
BOOL CBLIsOfflineError( NSError* error );

/** Returns YES if this is a network/HTTP error that is likely to be transient.
    Examples are timeout, connection lost, 502 Bad Gateway... */
BOOL CBLMayBeTransientError( NSError* error );

/** Returns YES if this is a network/HTTP error that should be considered permanent, i.e.
    the problem probably lies with the local setup (wrong URL or wrong credentials.) */
BOOL CBLIsPermanentError( NSError* error );

/** Returns YES if this error appears to be due to a creating a file/dir that already exists. */
BOOL CBLIsFileExistsError( NSError* error );

/** Removes a file if it exists; does nothing if it doesn't. */
BOOL CBLRemoveFileIfExists(NSString* path, NSError** outError) __attribute__((nonnull(1)));

/** Returns the input URL without the query string or fragment identifier, just ending with the path. */
NSURL* CBLURLWithoutQuery( NSURL* url ) __attribute__((nonnull));

/** Appends path components to a URL. These will NOT be URL-escaped, so you can include queries. */
NSURL* CBLAppendToURL(NSURL* baseURL, NSString* toAppend) __attribute__((nonnull));
