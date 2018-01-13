//
//  CBLQueryVariableExpression+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/12/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLQueryVariableExpression.h"
#import "CBLQueryJSONEncoding.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryVariableExpression ()

@property (readonly, nonatomic) NSString* name;

- (instancetype) initWithName: (NSString*)name;

@end

NS_ASSUME_NONNULL_END

