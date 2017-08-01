//
//  CBLBinaryExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CBLBinaryExpType) {
    CBLAddBinaryExpType,
    CBLBetweenBinaryExpType,
    CBLDivideBinaryExpType,
    CBLEqualToBinaryExpType,
    CBLGreaterThanBinaryExpType,
    CBLGreaterThanOrEqualToBinaryExpType,
    CBLInBinaryExpType,
    CBLIsBinaryExpType,
    CBLIsNotBinaryExpType,
    CBLLessThanBinaryExpType,
    CBLLessThanOrEqualToBinaryExpType,
    CBLLikeBinaryExpType,
    CBLMatchesBinaryExpType,
    CBLModulusBinaryExpType,
    CBLMultiplyBinaryExpType,
    CBLNotEqualToBinaryExpType,
    CBLSubtractBinaryExpType,
    CBLRegexLikeBinaryExpType
};

@interface CBLBinaryExpression: CBLQueryExpression

@property(nonatomic, readonly) id lhs;
@property(nonatomic, readonly) id rhs;
@property(nonatomic, readonly) CBLBinaryExpType type;

- (instancetype) initWithLeftExpression: (id)lhs
                        rightExpression: (id)rhs
                                   type: (CBLBinaryExpType)type;

@end

NS_ASSUME_NONNULL_END
