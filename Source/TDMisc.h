//
//  TDMisc.h
//  TouchDB
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TDRevision.h"

extern NSString* const TDHTTPErrorDomain;

NSString* TDCreateUUID( void );

NSString* TDHexSHA1Digest( NSData* input );

NSError* TDHTTPError( int status, NSURL* url );

NSComparisonResult TDSequenceCompare( SequenceNumber a, SequenceNumber b);

/** Escapes a string to be used as the value of a parameter in a URL.
    This does the usual %-escaping, but makes sure that '&' is also escaped. */
NSString* TDEscapeURLParam( NSString* param );