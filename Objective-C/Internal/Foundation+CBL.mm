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

@implementation NSString (CBL)
- (C4Slice) c4slice {
    return {self.UTF8String, self.length};
}

@end

@implementation NSURL (CBL)
- (void) c4Address: (C4Address*)addr {
    addr->scheme = self.scheme.c4slice;
    addr->hostname = self.host.c4slice;
    addr->port = self.port.unsignedShortValue;
    addr->path = self.path.stringByDeletingLastPathComponent.c4slice;
}

@end
