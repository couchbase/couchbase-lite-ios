//
//  CBLPrediction.mm
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc. All rights reserved.
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

#import "CBLPrediction+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLDocument+Internal.h"
#import "CBLFleece.hh"
#import "CBLNewDictionary.h"
#import "CBLStatus.h"
#import "c4PredictiveQuery.h"
#import "fleece/Fleece.hh"

using namespace fleece;

@implementation CBLPrediction {
    NSMutableDictionary *_models; // For retaining the registered models
}

static CBLPrediction* sInstance;

+ (instancetype) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[self alloc] init];
    });
    return sInstance;
}

- (void) registerModel: (id<CBLPredictiveModel>)model withName: (NSString*)name {
    CBLAssertNotNil(model);
    CBLAssertNotNil(name);
    
    CBL_LOCK(self) {
        // Setup callback object:
        auto callback = [](void* context, FLDict input, C4Error *outError) {
            @autoreleasepool {
                id<CBLPredictiveModel>m = (__bridge id<CBLPredictiveModel>)context;
                NSDictionary* dict = Dict(input).asNSObject();
                CBLDictionary* i = (id)[[CBLNewDictionary alloc] initWithDictionary: dict];
                CBLDictionary* o = [m prediction: i];
                if (!o)
                    return C4SliceResult{};
                
                NSError* error;
                FLSliceResult result = [o encode: &error];
                if (!result.buf)
                    convertError(error, outError);
                return result;
            }
        };
        
        // Retain the registered model object:
        if (!_models)
            _models = [NSMutableDictionary dictionary];
        [_models setObject: model forKey: name];
        
        // Register model:
        C4PredictiveModel predModel = {.context = (__bridge void*)model, .prediction = callback};
        c4pred_registerModel(name.UTF8String, predModel);
    }
}

- (void) unregisterModelWithName: (NSString*)name {
    CBLAssertNotNil(name);
    
    CBL_LOCK(self) {
        c4pred_unregisterModel(name.UTF8String);
        [_models removeObjectForKey: name];
    }
}

@end
