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
#import "CBLPrediction+Swift.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLFleece.hh"
#import "CBLNewDictionary.h"
#import "CBLStatus.h"
#import "c4PredictiveQuery.h"
#import "fleece/Fleece.hh"
#import "MRoot.hh"

using namespace fleece;

@interface CBLPredictiveModelBridge : NSObject <CBLPredictiveModel>
- (instancetype) initWithBlock: (CBLPredictiveModelBlock)model;
@end

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
        auto callback = [](void* context, FLDict input, C4Database* c4db, C4Error *outError) {
            @autoreleasepool {
                id<CBLPredictiveModel> m = (__bridge id<CBLPredictiveModel>)context;
                CBLDatabase* db = [[CBLDatabase alloc] initWithC4Database: c4db];
                MRoot<id> root(new cbl::DocContext(db, nullptr), (FLValue)input, false);
                CBLDictionary* dict = root.asNative();
                CBLDictionary* output = [m predict: dict];
                return encodePrediction(output, outError);
            }
        };
        
        // Retain the registered model object:
        if (!_models)
            _models = [NSMutableDictionary dictionary];
        
        // If there is a model registered with the same name, unregister the current one first:
        if ([_models objectForKey: name])
            [self unregisterModelWithName: name];
        
        // Save the model in a dictionary:
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


static C4SliceResult encodePrediction(CBLDictionary* prediction, C4Error* outError) {
    if (!prediction)
        return C4SliceResult{};
    
    FLError err;
    FLEncoder enc = FLEncoder_New();
    [prediction fl_encodeToFLEncoder: enc];
    FLSliceResult result = FLEncoder_Finish(enc, &err);
    FLEncoder_Free(enc);
    if (err != 0)
        convertError(err, outError);
    return result;
}


#pragma mark - Swift


- (void) registerModelWithName: (NSString*)name usingBlock: (CBLPredictiveModelBlock)block {
    CBLPredictiveModelBridge* model = [[CBLPredictiveModelBridge alloc] initWithBlock: block];
    [self registerModel: model withName: name];
}

@end


@implementation CBLPredictiveModelBridge {
    CBLPredictiveModelBlock _model;
}

- (instancetype) initWithBlock: (CBLPredictiveModelBlock)block {
    self = [super init];
    if (self) {
        _model = block;
    }
    return self;
}


- (nullable CBLDictionary *)predict:(nonnull CBLDictionary *)input {
    return _model(input);
}

@end
