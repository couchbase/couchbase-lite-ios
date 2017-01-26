//
//  CBLBlobStream.h
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "c4BlobStore.h"

// A convenience class for wrapping C4ReadStream
@interface CBLBlobStream : NSInputStream

// Create a stream based on the given store and key (this allows it to be created multiple times
// so that it can be read more than once if need be)
- (instancetype)initWithStore:(C4BlobStore *)store
                          key:(C4BlobKey)key
                        error:(NSError **)error;


@end
