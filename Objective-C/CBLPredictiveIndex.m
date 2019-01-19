//
//  CBLPredictiveIndex.m
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

#import "CBLPredictiveIndex.h"
#import "CBLIndex+Internal.h"
#import "CBLQueryExpression+Internal.h"
#import "CBLPredictiveIndex+Internal.h"

@implementation CBLPredictiveIndex {
    NSString* _model;
    CBLQueryExpression* _input;
    NSArray<NSString*>* _properties;
}


- (instancetype) initWithModel: (NSString*)model
                         input: (CBLQueryExpression*)input
                    properties: (nullable NSArray<NSString*>*)properties {
    self = [super initWithNone];
    if (self) {
        _model = model;
        _input = input;
        _properties = properties;
    }
    return self;
}


- (C4IndexType) indexType {
    return kC4PredictiveIndex;
}


- (C4IndexOptions) indexOptions {
    return (C4IndexOptions){ };
}


- (id) indexItems {
    NSMutableArray* items = [NSMutableArray array];
    [items addObject: @"PREDICTION()"];
    [items addObject: _model];
    [items addObject: [_input asJSON]];
    
    for (NSString* keyPath in _properties) {
        [items addObject: [NSString stringWithFormat: @".%@", keyPath]];
    }
    
    NSMutableArray* json = [NSMutableArray array];
    [json addObject: items];
    return json;
}

@end
