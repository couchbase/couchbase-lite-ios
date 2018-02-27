//
//  CBLDocumentFragment.m
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

#import "CBLDocumentFragment.h"
#import "CBLDocument.h"
#import "CBLDocument+Internal.h"

@implementation CBLDocumentFragment {
    CBLDocument* _doc;
}

- /* internal */ (instancetype) initWithDocument: (CBLDocument*)document {
    self = [super init];
    if (self) {
        _doc = document;
    }
    return self;
}


- (BOOL) exists {
    return _doc != nil;
}


- (CBLDocument*) document {
    return _doc;
}


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    return _doc ? _doc[key] : nil;
}


@end
