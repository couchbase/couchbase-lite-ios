//
//  CBLCompoundExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CBLCompoundExpType) {
    CBLAndCompundExpType,
    CBLOrCompundExpType,
    CBLNotCompundExpType
};

@interface CBLCompoundExpression: CBLQueryExpression

- (instancetype) initWithExpressions: (NSArray*)expressions type: (CBLCompoundExpType)type;

@end

NS_ASSUME_NONNULL_END
