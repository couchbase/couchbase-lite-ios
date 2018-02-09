//
//  CBLReplicator+Internal.h
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

#import "CBLReplicator.h"
#import "CBLReplicatorConfiguration.h"
#import "c4.h"
@class MYBackgroundMonitor;

NS_ASSUME_NONNULL_BEGIN


@interface CBLReplicatorConfiguration ()

@property (readonly, nonatomic) NSDictionary* effectiveOptions;
@property (nonatomic) NSTimeInterval checkpointInterval;
@property (nonatomic) NSTimeInterval heartbeatInterval;

- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config
                       readonly: (BOOL)readonly;

@end


@interface CBLReplicator () {
    // For CBLReplicator+Backgrounding:
    BOOL _deepBackground;
    BOOL _filesystemUnavailable;
}

@property (readonly, atomic) BOOL active;
@property (atomic) BOOL suspended;
@property (nonatomic) MYBackgroundMonitor* bgMonitor;

@end

NS_ASSUME_NONNULL_END
