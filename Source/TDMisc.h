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

int TDSequenceCompare( SequenceNumber a, SequenceNumber b);
