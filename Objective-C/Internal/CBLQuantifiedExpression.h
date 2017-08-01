//
//  CBLQuantifiedExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CBLQuantifiedType) {
    CBLQuantifiedTypeAny,
    CBLQuantifiedTypeAnyAndEvery,
    CBLQuantifiedTypeEvery
};

@interface CBLQuantifiedExpression : CBLQueryExpression

- (instancetype) initWithType: (CBLQuantifiedType)type
                     variable: (NSString*)variable
                           in: (id)inExpression
                    satisfies: (id)satisfiesExpression;

@end

NS_ASSUME_NONNULL_END
