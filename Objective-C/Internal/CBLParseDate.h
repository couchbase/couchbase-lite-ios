//
//  CBLParseDate.h
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-ios/blob/master/Source/CBLParseDate.h
//  Created by Jens Alfke on 9/8/13.
//
//  Created by Pasin Suriyentrakorn on 1/4/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#ifndef CouchbaseLite_CBLParseDate_h
#define CouchbaseLite_CBLParseDate_h

/** Parses a C string as an ISO-8601 date-time, returning a UNIX timestamp (number of seconds
    since 1/1/1970), or a NAN if the string is not valid. */
double CBLParseISO8601Date(const char* dateStr);

#endif
