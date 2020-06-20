//
//  CBLCookie.m
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc All rights reserved.
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

#import "CBLCookie.h"
#import "CBLCoreBridge.h"
#import "CBLReplicator+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CollectionUtils.h"
#import "CBLURLEndpoint.h"
#import "Foundation+CBL.h"

@implementation CBLCookie

+ (NSString*) getCookiesForReplicator: (CBLReplicator*)r {
    C4Address addr = {};
    NSURL* remoteURL = $castIf(CBLURLEndpoint, r.config.target).url;
    [remoteURL c4Address: &addr];
    
    C4Error err = {};
    C4SliceResult cookies = c4db_getCookies(r.config.database.c4db, addr, &err);
    NSString* result = sliceResult2string(cookies);
    return result;
}


@end
