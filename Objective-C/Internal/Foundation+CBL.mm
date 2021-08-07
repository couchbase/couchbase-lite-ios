//
//  Foundation+CBL.mm
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

#import "Foundation+CBL.h"
#import "CBLStringBytes.h"

@implementation NSURL (CBL)
- (void) c4Address: (C4Address*)addr {
    CBLStringBytes schemeSlice(self.scheme);
    CBLStringBytes hostSlice(self.host);
    CBLStringBytes pathSlice(self.path.stringByDeletingLastPathComponent);
    
    addr->scheme = schemeSlice;
    addr->hostname = hostSlice;
    addr->port = self.port.unsignedShortValue;
    addr->path = pathSlice;
}

@end

@implementation NSString (CBL)
- (id) toJSONObj {
    NSData* d = [self dataUsingEncoding: NSUTF8StringEncoding];
    
    NSError* error;
    id retrivedObj = [NSJSONSerialization JSONObjectWithData: d options: 0
                                                       error: &error];
    AssertNil(error);
    return retrivedObj;
}

@end

@implementation NSObject (CBL)
- (void) useLock: (void (^)(void))block {
    CBL_LOCK(self) {
        block();
    }
}
@end
