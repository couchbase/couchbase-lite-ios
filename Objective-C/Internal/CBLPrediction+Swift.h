//
//  CBLPrediction+Swift.h
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLPrediction.h"

NS_ASSUME_NONNULL_BEGIN

typedef CBLDictionary* __nullable (^CBLPredictiveModelBlock)(CBLDictionary*);

@interface CBLPrediction ()

- (void) registerModelWithName: (NSString*)name usingBlock: (CBLPredictiveModelBlock)block;

@end

NS_ASSUME_NONNULL_END
