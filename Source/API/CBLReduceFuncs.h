//
//  CBLReduceFuncs.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/15/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

#import <Couchbaselite/CBLView.h>

#if __has_feature(nullability) // Xcode 6.3+
#pragma clang assume_nonnull begin
#else
#define nullable
#define __nullable
#endif


void CBLRegisterReduceFunc(NSString* name, CBLReduceBlock block);

__nullable CBLReduceBlock CBLGetReduceFunc(NSString* name);



#if __has_feature(nullability)
#pragma clang assume_nonnull end
#endif
