//
//  CBLIndexConfiguration.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/7/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLIndexConfiguration : NSObject
- (instancetype) init NS_UNAVAILABLE;

@end

@protocol CBLIndexConfigurationProtocol <NSObject>
- (instancetype) initWithExpression: (NSString*)expression;

@end

@interface CBLFullTextIndexConfiguration: CBLIndexConfiguration <CBLIndexConfigurationProtocol>
@end

@interface CBLValueIndexConfiguration : CBLIndexConfiguration <CBLIndexConfigurationProtocol>
@end

NS_ASSUME_NONNULL_END
