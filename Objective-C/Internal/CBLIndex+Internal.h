//
//  CBLIndex+Internal.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#pragma once
#import "c4.h"
#import "CBLIndex.h"
#import "CBLFullTextIndex.h"
#import "CBLValueIndex.h"
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

@interface CBLIndex ()

- (instancetype) initWithNone;

@property (readonly) C4IndexType indexType;

@property (readonly) C4IndexOptions indexOptions;

@property (readonly, nullable) id indexItems;

@end

@interface CBLFullTextIndex ()

- (instancetype) initWithItems: (NSArray<CBLFullTextIndexItem*>*)items;

@end

@interface CBLValueIndex ()

- (instancetype) initWithItems: (NSArray<CBLValueIndexItem*>*)items;

@end

@interface CBLValueIndexItem ()

@property (nonatomic, readonly) CBLQueryExpression* expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

@interface CBLFullTextIndexItem ()

@property (nonatomic, readonly) CBLQueryExpression* expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

NS_ASSUME_NONNULL_END
