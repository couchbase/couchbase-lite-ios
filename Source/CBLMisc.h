//
//  CBLMisc.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Database sequence ID */
typedef SInt64 SequenceNumber;


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

/** Writes a hex dump of the bytes to the output string.
    Returns a pointer to the end of the string (where it writes a null.) */
char* CBLAppendHex( char *dst, const void* bytes, size_t length);

/** Appends a decimal number to the output string. */
size_t CBLAppendDecimal(char *buf, uint64_t n);

/** Generates a digest string from a JSON-encodable object. Equal objects produce equal strings. */
NSString* CBLDigestFromObject(id obj);

/** Generates a hex dump of a sequence of bytes.
    The result is lowercase. This is important for CouchDB compatibility. */
NSString* CBLHexFromBytes( const void* bytes, size_t length) __attribute__((nonnull));

/** Parses hex dump to NSData. Returns nil if length is odd or any character is not a hex digit. */
NSData* CBLDataFromHex(NSString* hex);

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

/** Returns YES if this error appears to be due to a missing file. */
BOOL CBLIsFileNotFoundError( NSError* error );

/** Returns YES if this error appears to be due to a creating a file/dir that already exists. */
BOOL CBLIsFileExistsError( NSError* error );

/** Removes a file if it exists; does nothing if it doesn't. */
BOOL CBLRemoveFileIfExists(NSString* path, NSError** outError) __attribute__((nonnull(1)));

/* Remove a file asynchronously if it exists; does nothing if it doesn't.
   The file will be moved to the temp folder and renamed before it is deleted. */
BOOL CBLRemoveFileIfExistsAsync(NSString* path, NSError** outError);

/* Copy a file if it exists; does nothing if it doesn't. */
BOOL CBLCopyFileIfExists(NSString*atPath, NSString* toPath, NSError** outError) __attribute__((nonnull(1, 2)));

/** Replaces the directory at dstPath with the one at srcPath. (Both must already exist.)
    Afterwards, on success, there will be a dir at dstPath but not at srcPath.
    For safety's sake, the old directory is moved aside, then the new directory is moved in,
    and only then is the old directory deleted. */
BOOL CBLSafeReplaceDir(NSString* srcPath, NSString* dstPath, NSError** outError);

/** Returns the hostname of this computer/device (will be of the form "___.local") */
NSString* CBLGetHostName(void);

/** Returns the input URL without the query string or fragment identifier, just ending with the path. */
NSURL* CBLURLWithoutQuery( NSURL* url ) __attribute__((nonnull));

/** Appends path components to a URL. These will NOT be URL-escaped, so you can include queries. */
NSURL* CBLAppendToURL(NSURL* baseURL, NSString* toAppend) __attribute__((nonnull));

/** Changes a given query max key into one that also extends to any key it matches as a prefix. */
id CBLKeyForPrefixMatch(id key, unsigned depth);

/** Stemmer name to use for the sqlite3-unicodesn tokenizer, based on current locale's language. */
NSString* CBLStemmerNameForCurrentLocale(void);

#if DEBUG
NSString* CBLPathToTestFile(NSString* name);
NSData* CBLContentsOfTestFile(NSString* name);
#endif
