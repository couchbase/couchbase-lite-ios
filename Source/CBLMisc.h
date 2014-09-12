//
//  CBLMisc.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBL_Revision.h"


// In a method/function implementation (not declaration), declaring an object parameter as
// __unsafe_unretained avoids the implicit retain at the start of the function and releasse at
// the end. In a performance-sensitive function, those can be significant overhead. Of course this
// should never be used if the object might be released during the function.
#define UU __unsafe_unretained


extern NSString* const CBLHTTPErrorDomain;

BOOL CBLWithStringBytes(NSString* str, void (^block)(const char*, size_t));

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

/** Convenience function to JSON-encode an object to a string. */
NSString* CBLJSONString( id object );

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

/** Parses a string to an integer. Returns YES on success, NO on failure.
    Fails on strings that start numeric but contain junk afterwards, like "123*foo".
    You may pass NULL for outInt if you don't care about the numeric value. */
BOOL CBLParseInteger(NSString* str, NSInteger* outInt);

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


#if DEBUG
NSString* CBLPathToTestFile(NSString* name);
NSData* CBLContentsOfTestFile(NSString* name);
#endif