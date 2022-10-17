//
//  CBLRemoteDocument.m
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

#import "CBLRemoteDocument.h"
#import "CBLFleece.hh"
#include "fleece/FLExpert.h"

using namespace fleece;

@implementation CBLRemoteDocument {
    FLDict _dict;
}

@synthesize body=_body;

- (instancetype) initWithBody:(FLSliceResult)body {
    self = [self init];
    if (self) {
        // keeps a retained copy of body for CBLDocument & releases in dealloc
        _body = FLSliceResult_Retain(body);
        
        _dict = kFLEmptyDict;
        if (body.buf) {
            FLValue docBodyVal = FLValue_FromData(slice(_body), kFLTrusted);
            _dict = FLValue_AsDict(docBodyVal);
        }
    }
    return self;
}

- (FLDict) data {
    return _dict;
}

- (void) dealloc {
    if (_body)
        FLSliceResult_Release(_body); // releases the retained copy
}

@end
