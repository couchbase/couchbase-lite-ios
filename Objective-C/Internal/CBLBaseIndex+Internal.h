//
//  CBLBaseIndex.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/7/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "c4.h"

NS_ASSUME_NONNULL_BEGIN

@protocol CBLBaseIndexProtocol <NSObject>

@property (nonatomic, readonly) C4QueryLanguage queryLanguage;
@property (nonatomic, readonly) C4IndexType indexType;
@property (readonly) NSString* getIndexSpecs;
@property (readonly) C4IndexOptions indexOptions;

- (instancetype) initWithIndexType: (C4IndexType)indexType
                     queryLanguage: (C4QueryLanguage)language;

@end

@interface CBLBaseIndex () <CBLBaseIndexProtocol>
@end

NS_ASSUME_NONNULL_END
