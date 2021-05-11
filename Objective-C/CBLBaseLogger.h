//
//  CBLBaseLogger.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 4/25/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLLogger.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLBaseLogger : NSObject

@property (readonly, nonatomic) CBLLogLevel level;

@property (readonly, nonatomic) CBLLogDomain domains;

- (instancetype) initWithLevel: (CBLLogLevel)level;

- (instancetype) initWithLevel: (CBLLogLevel)level domains: (CBLLogDomain)domains;

- (instancetype) init NS_UNAVAILABLE;

- (void) logWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message;

- (void) writeLog: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message;

@end

NS_ASSUME_NONNULL_END
