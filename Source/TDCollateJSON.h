//
//  TDCollator.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/** SQLite collation function for JSON-formatted strings.
    The "context" parameter should be one of the three collation mode constants below.
    WARNING: This function *only* works on valid JSON with no whitespace.
    If called on non-JSON strings it is quite likely to crash! */
int TDCollateJSON(void *context,
               int len1, const void * chars1,
               int len2, const void * chars2);

/** Collation that compares only a limited number of top-level collection items.
    If the first 'arrayLimit' items of the top-level array/object have been parsed and are equal, it will stop and return 0. (This is useful for view result grouping.) */
int TDCollateJSONLimited(void *context,
                         int len1, const void * chars1,
                         int len2, const void * chars2,
                         unsigned arrayLimit);

// CouchDB's default collation rules, including Unicode collation for strings
#define kTDCollateJSON_Unicode ((void*)0)

// CouchDB's "raw" collation rules (which order scalar types differently, beware)
#define kTDCollateJSON_Raw ((void*)1)

// ASCII mode, which is like CouchDB default except that strings are compared as binary UTF-8
#define kTDCollateJSON_ASCII ((void*)2)
