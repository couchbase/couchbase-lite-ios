//
//  CBLEncoder.h
//  CouchbaseLite
//
//  Created by Callum Birks on 10/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDatabase.h"
#import "CBLDictionary.h"

@class CBLEncoder;
@class CBLEncoderContext;

NS_ASSUME_NONNULL_BEGIN

@interface CBLEncoder : NSObject

- (nullable instancetype) initWithDB: (CBLDatabase*)db
                 error: (NSError**)error;

- (void) setExtraInfo: (CBLEncoderContext*)context;

- (void) reset;
- (nullable NSString*) getError;

- (bool) writeKey: (NSString*)key;
- (bool) write: (id)obj;

- (bool) beginArray: (NSUInteger)reserve;
- (bool) endArray;
- (bool) beginDict: (NSUInteger)reserve;
- (bool) endDict;

- (nullable NSData*) finish;
- (bool) finishInto: (CBLDocument*)document;

@end

@interface CBLEncoderContext : NSObject <NSCopying>

- (instancetype) initWithDB: (CBLDatabase*)db;
- (nonnull void*) get;
- (void) reset;

@end

NS_ASSUME_NONNULL_END
