//
//  CBLParseDate.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/8/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#ifndef CouchbaseLite_CBLParseDate_h
#define CouchbaseLite_CBLParseDate_h

/** Parses a C string as an ISO-8601 date-time, returning a UNIX timestamp (number of seconds
    since 1/1/1970), or a NAN if the string is not valid. */
double CBLParseISO8601Date(const char* dateStr);

#endif
