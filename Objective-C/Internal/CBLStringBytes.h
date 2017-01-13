//
//  CBLStringBytes.h
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-core/blob/master/Objective-C/StringBytes.hh
//  Created by Jens Alfke on 10/13/16.
//
//  Created by Pasin Suriyentrakorn on 1/4/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

#pragma once
#import <Foundation/Foundation.h>
#import "c4Base.h"
#import "Fleece.h"


/** A slice holding the data of an NSString. If possible, it points the slice into the data of the
 NSString, requiring no copying. Otherwise it copies the characters into a small internal
 buffer, or into a temporary heap block.
 
 NOTE: Since the slice may point directly into the NSString, if the string is mutable do not
 mutate it while the stringBytes object is in scope! (Releasing the string is OK, as
 stringBytes retains it.) */
struct CBLStringBytes  {
    CBLStringBytes(NSString* =nil);
    ~CBLStringBytes();
    
    void operator= (NSString*);
    
    operator FLSlice() const {return {buf, size};}
    operator C4Slice() const {return {buf, size};}
    
    const char *buf;
    size_t size;
    
private:
    __strong NSString *_string {nullptr};
    char _local[127];
    bool _needsFree {false};
};
