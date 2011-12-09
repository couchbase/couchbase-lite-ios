//
//  ToyCollator.h
//  ToyCouch
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/** SQLite collation function for JSON-formatted strings.
    Compares them according to CouchDB's collation rules.
    WARNING: This function *only* works on valid JSON with no whitespace.
    If called on non-JSON strings it is quite likely to crash! */
int ToyCollate(void *context,
               int len1, const void * chars1,
               int len2, const void * chars2);
