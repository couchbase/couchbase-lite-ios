//
//  CBLBlob.h
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLBlob : NSObject

@property (readonly, nonatomic, nullable) NSData* content;

@property (readonly, nonatomic) NSInputStream *contentStream;

@property (readonly, nonatomic) NSString* contentType;

@property (readonly) NSInteger length;

@property (readonly, nullable) NSString* digest;

@property (readonly, nonatomic) NSDictionary* properties;

- (instancetype) initWithContentType:(NSString *)contentType
                                data:(NSData *) data;

- (instancetype) initWithContentType:(NSString *)contentType
                                contentStream:(NSInputStream *)stream;

- (instancetype) initWithContentType:(NSString *)contentType
                                fileURL:(NSURL*)url;

@end

NS_ASSUME_NONNULL_END
