//
//  CBLWebSocket.h
//  LiteCore
//
//  Created by Jens Alfke on 3/14/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


@interface CBLWebSocket : NSObject <NSURLSessionStreamDelegate>

+ (void) registerWithC4;

@end


NS_ASSUME_NONNULL_END
