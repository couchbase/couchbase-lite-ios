//
//  TDMisc.h
//  TouchDB
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


NSString* TDCreateUUID( void );

NSString* TDHexSHA1Digest( NSData* input );
