//
//  CBLQueryFullTextIndexExpressionProtocol.h
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Index Expression. */
@protocol CBLQueryIndexExpressionProtocol <NSObject>

@end

/** Full-Text Index Expression. */
@protocol CBLQueryFullTextIndexExpressionProtocol <CBLQueryIndexExpressionProtocol>

/**
 Specifies an alias name of the data source in which the index has been created.
 ss
 - Parameter alias: The alias name of the data source.
 - Returns: The full-text index expression referring to a full text index in the specified data source.
 */
- (id<CBLQueryIndexExpressionProtocol>) from: (NSString*)alias;

@end

NS_ASSUME_NONNULL_END
