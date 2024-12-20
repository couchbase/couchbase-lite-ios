//
//  CBLLogSinks+Internal.h
//  CouchbaseLite
//
//  Created by Vlad Velicu on 16/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import "CBLLogSinks.h"
#import "CBLLogTypes.h"
#import "CBLConsoleLogSink.h"
#import "CBLCustomLogSink.h"
#import "CBLFileLogSink.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, LogAPI) {
    LogAPINone,
    LogAPIOld,
    LogAPINew,
};

@interface CBLLogSinks ()

+ (void) writeCBLLog: (C4LogDomain)domain level: (C4LogLevel)level message: (NSString*)message;

+ (void) checkLogApiVersion: (LogAPI) version;

@end

@interface CBLConsoleLogSink () <CBLLogSinkProtocol>

@end

@interface CBLCustomLogSink () <CBLLogSinkProtocol>

@end

@interface CBLFileLogSink ()

+ (void) setup: (nullable CBLFileLogSink*)logSink;

@end

NS_ASSUME_NONNULL_END
