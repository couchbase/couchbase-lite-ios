//
//  CBLEncoder.h
//  CouchbaseLite
//
//  Created by Callum Birks on 10/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "fleece/Fleece.h"
#import "CBLDatabase.h"

@class CBLEncoder;

NS_ASSUME_NONNULL_BEGIN

@interface CBLEncoder : NSObject <NSCopying>

- (instancetype) init;
- (instancetype) initWithFLEncoder: (FLEncoder)enc;
- (instancetype) initWithSharedKeys: (FLSharedKeys)sk;
- (instancetype) initWithDB: (CBLDatabase*)db;

- (void) reset;
- (nullable NSString*) getError;

- (bool) writeKey: (NSString*)key;
- (bool) write: (id)obj;

- (bool) beginArray: (NSUInteger)reserve;
- (bool) endArray;
- (bool) beginDict: (NSUInteger)reserve;
- (bool) endDict;

- (nullable NSData*) finish;

@end

NS_ASSUME_NONNULL_END
