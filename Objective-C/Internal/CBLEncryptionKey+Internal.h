//
//  CBLEncryptionKey+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLEncryptionKey.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLEncryptionKey ()

@property (atomic, readonly) NSData* key;

@end

NS_ASSUME_NONNULL_END
