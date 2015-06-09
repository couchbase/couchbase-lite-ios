//
//  CBLReduceFuncs.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/15/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

#import <Couchbaselite/CBLView.h>

NS_ASSUME_NONNULL_BEGIN

void CBLRegisterReduceFunc(NSString* name, CBLReduceBlock block);

__nullable CBLReduceBlock CBLGetReduceFunc(NSString* name);



NS_ASSUME_NONNULL_END
