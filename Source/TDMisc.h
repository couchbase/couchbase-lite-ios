//
//  TDMisc.h
//  TouchDB
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TouchDB/TDRevision.h>

extern NSString* const TDHTTPErrorDomain;

NSString* TDCreateUUID( void );

NSData* TDSHA1Digest( NSData* input );
NSData* TDSHA256Digest( NSData* input );

NSString* TDHexSHA1Digest( NSData* input );

NSData* TDHMACSHA1(NSData* key, NSData* data);
NSData* TDHMACSHA256(NSData* key, NSData* data);

/** Generates a hex dump of a sequence of bytes.
    The result is lowercase. This is important for CouchDB compatibility. */
NSString* TDHexFromBytes( const void* bytes, size_t length);

NSComparisonResult TDSequenceCompare( SequenceNumber a, SequenceNumber b);

/** Escapes a document or revision ID for use in a URL.
    This does the usual %-escaping, but makes sure that '/' is escaped in case the ID appears in the path portion of the URL, and that '&' is escaped in case the ID appears in a query value. */
NSString* TDEscapeID( NSString* param );

/** Escapes a string to be used as the value of a query parameter in a URL.
    This does the usual %-escaping, but makes sure that '&' is also escaped. */
NSString* TDEscapeURLParam( NSString* param );

/** Wraps a string in double-quotes and prepends backslashes to any existing double-quote or backslash characters in it. */
NSString* TDQuoteString( NSString* param );

/** Undoes effect of TDQuoteString, i.e. removes backslash escapes and any surrounding double-quotes.
    If the string has no surrounding double-quotes it will be returned as-is. */
NSString* TDUnquoteString( NSString* param );

/** Returns YES if this error appears to be due to the computer being offline or the remote host being unreachable. */
BOOL TDIsOfflineError( NSError* error );

/** Returns YES if this is a network/HTTP error that is likely to be transient.
    Examples are timeout, connection lost, 502 Bad Gateway... */
BOOL TDMayBeTransientError( NSError* error );

/** Returns YES if this error appears to be due to a creating a file/dir that already exists. */
BOOL TDIsFileExistsError( NSError* error );

/** Returns the input URL without the query string or fragment identifier, just ending with the path. */
NSURL* TDURLWithoutQuery( NSURL* url );
