//
//  CBLFileLogSink.h
//  CouchbaseLite
//
//  Created by Vlad Velicu on 02/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CBLLogSinkProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLFileLogSink : NSObject

/**
 The minimum log level of the log messages to be logged. The default log level for
 file logger is kCBLLogLevelNone which means no logging.
 */
@property (nonatomic, assign, readonly) CBLLogLevel level;

/** The set of log domains of the log messages to be logged. By default, the log
    messages of all domains will be logged. */
@property (nonatomic, assign, readonly) CBLLogDomain domain;

/**
 The directory to store the log files.
 */
@property (nonatomic, copy, readonly) NSString* directory;

/**
 To use plain text file format instead of the default binary format.
 */
@property (nonatomic, assign, readonly) BOOL usePlainText;

/**
 The maximum size of a log file before being rotated in bytes.
 The default is ``kCBLDefaultMaxKeptFiles``
 */
@property (nonatomic, assign, readonly) uint64_t maxKeptFiles;

/**
 The Max number of rotated log files to keep.
 The default value is ``kCBLDefaultMaxFileSize``
 */
@property (nonatomic, assign, readonly) NSInteger maxFileSize;

- (instancetype) initWithLevel: (CBLLogLevel) level
                        domain: (CBLLogDomain) domain
                     directory: (NSString*) directory;

- (instancetype) initWithLevel: (CBLLogLevel) level
                        domain: (CBLLogDomain) domain
                     directory: (NSString*) directory
                  usePlainText: (BOOL) usePlainText
                  maxKeptFiles: (uint64_t) maxKeptFiles
                   maxFileSize: (NSInteger) maxFileSize;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
