//
//  CBLReplicationConflictResolver.m
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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

#import "CBLConflictResolverService.h"
#import "CBLCollection+Internal.h"
#import "CBLDocumentReplication+Internal.h"

typedef NS_ENUM(NSInteger, CBLConflictResolverState) {
    CBLConflictResolverRunning = 0,
    CBLConflictResolverStopping,
    CBLConflictResolverStopped
};

@implementation CBLConflictResolverService {
    dispatch_queue_t _queue;
    NSMutableArray<dispatch_block_t>* _pendingBlocks;
    
    id _mutex;
    CBLConflictResolverState _state;
    void (^_pendingShutdownCompletion)(void);
}

- (instancetype) initWithReplicatorID: (NSString*)replicatorID {
    self = [super init];
    if (self) {
        NSString* name = $sprintf(@"ConflictResolverService [%@]", replicatorID);
        _queue = dispatch_queue_create(name.UTF8String, DISPATCH_QUEUE_CONCURRENT);
        _pendingBlocks = [NSMutableArray array];
        _mutex = [[NSObject alloc] init];
        _state = CBLConflictResolverRunning;
    }
    return self;
}

- (BOOL) shutdownAndWait: (BOOL)waitForPendingTasks completion: (void (^)(void))completion {
    NSArray<dispatch_block_t> *blocksToCancel;
    
    CBL_LOCK(_mutex) {
        if (_state != CBLConflictResolverRunning) {
            return NO;
        }
        
        if (_pendingBlocks.count == 0) {
            _state = CBLConflictResolverStopped;
            dispatch_async(_queue, ^{
                completion();
            });
            return YES;
        }
        
        _state = CBLConflictResolverStopping;
        _pendingShutdownCompletion = completion;
        
        if (!waitForPendingTasks) {
            blocksToCancel = [_pendingBlocks copy];
        }
    }
    
    for (dispatch_block_t block in blocksToCancel) {
        dispatch_block_cancel(block);
    }
    
    return YES;
}

- (void) addConflict: (CBLReplicatedDocument*)doc
          collection: (CBLCollection*)collection
            resolver: (id<CBLConflictResolver>)resolver
          completion: (void (^)(BOOL cancelled, NSError* _Nullable error))completion {
    CBL_LOCK(_mutex) {
        if (_state != CBLConflictResolverRunning) {
            completion(YES, nil);
            return;
        }
        
        dispatch_block_t block = dispatch_block_create(0, ^{
            NSError* error = nil;
            if (![collection resolveConflictInDocument: doc.id
                                  withConflictResolver: resolver
                                                 error: &error]) {
                CBLWarn(Sync, @"%@ Conflict resolution of '%@' failed: %@", self, doc.id, error);
            }
            completion(NO, error);
        });
        
        dispatch_block_notify(block, _queue, ^{
            [self removePendingBlock: block];
        });
        
        [_pendingBlocks addObject:block];
        dispatch_async(_queue, block);
    }
}

- (void) removePendingBlock :(dispatch_block_t)block {
    CBL_LOCK(_mutex) {
        [_pendingBlocks removeObject: block];
        if (_state == CBLConflictResolverStopping && _pendingBlocks.count == 0) {
            _state = CBLConflictResolverStopped;
            void (^completion)(void) = _pendingShutdownCompletion;
            _pendingShutdownCompletion = nil;
            completion();
        }
    }
}

@end
