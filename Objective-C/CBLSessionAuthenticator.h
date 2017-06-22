//
//  CBLSessionAuthenticator.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLAuthenticator.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLSessionAuthenticator : CBLAuthenticator

@property (nonatomic, readonly, copy) NSString* sessionID;

@property (nonatomic, readonly, copy, nullable) NSDate* expires;

@property (nonatomic, readonly, copy) NSString* cookieName;

- (instancetype) initWithSessionID: (NSString*)sessionID
                           expires: (nullable id)expires
                        cookieName: (NSString*)cookieName;

@end

NS_ASSUME_NONNULL_END
