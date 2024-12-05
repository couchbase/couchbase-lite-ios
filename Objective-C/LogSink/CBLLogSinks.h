//
//  CBLLogSinks.h
//  CouchbaseLite
//
//  Created by Vlad Velicu on 02/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLConsoleLogSink.h"
#import "CBLFileLogSink.h"
#import "CBLCustomLogSink.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLLogSinks : NSObject

@property (nonatomic, nullable) CBLConsoleLogSink* console;

@property (nonatomic, nullable) CBLFileLogSink* file;

@property (nonatomic, nullable) CBLCustomLogSink* custom;

- (void)setConsoleSink: (CBLConsoleLogSink*) console;

- (void)setFileSink: (CBLFileLogSink*) file;

- (void)setCustomSink: (CBLCustomLogSink*)custom;

@end

NS_ASSUME_NONNULL_END
