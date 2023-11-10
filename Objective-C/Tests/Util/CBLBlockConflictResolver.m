//
//  CBLBlockConflictResolver.m
//  CouchbaseLite
//
//  Copyright (c) 2023 Couchbase, Inc. All rights reserved.
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

#import "CBLBlockConflictResolver.h"

@implementation CBLBlockConflictResolver {
    CBLDocument* (^_resolver)(CBLConflict*);
}

@synthesize winner=_winner;

// set this resolver, which will be used while resolving the conflict
- (instancetype) initWithResolver: (CBLDocument* (^)(CBLConflict*))resolver {
    self = [super init];
    if (self) {
        _resolver = resolver;
    }
    return self;
}

- (CBLDocument *) resolve:(CBLConflict *)conflict {
    _winner = _resolver(conflict);
    return _winner;
}

@end
