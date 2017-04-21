//
//  CBLError.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/19/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    kCBLErrorStatusForbidden = 403,
    kCBLErrorStatusNotFound = 404
} CBLErrorStatus;

NS_ASSUME_NONNULL_BEGIN

@interface CBLError : NSObject

+ (NSError*) createError: (CBLErrorStatus)status;

+ (NSError*) createError: (CBLErrorStatus)status description: (nullable NSString*)description;

@end

NS_ASSUME_NONNULL_END
