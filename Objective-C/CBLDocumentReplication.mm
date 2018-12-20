//
//  CBLDocumentReplication.m
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

#import "CBLDocumentReplication.h"
#import "CBLDocumentReplication+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLReplicator.h"
#import "CBLStatus.h"

@implementation CBLDocumentReplication

@synthesize replicator=_replicator, isPush=_isPush, documents=_documents;

- (instancetype) initWithReplicator: (CBLReplicator*)replicator
                             isPush: (BOOL)isPush
                          documents: (NSArray<CBLReplicatedDocument*>*)documents
{
    self = [super init];
    if (self) {
        _replicator = replicator;
        _isPush = isPush;
        _documents = documents;
    }
    return self;
}

@end


@implementation CBLReplicatedDocument

@synthesize id=_id, isDeleted=_isDeleted, isAccessRemoved=_isAccessRemoved;
@synthesize c4Error=_c4Error, isTransientError=_isTransientError;

- (instancetype) initWithC4DocumentEnded: (const C4DocumentEnded*)docEnded {
    self = [super init];
    if (self) {
        _id = slice2string(docEnded->docID);
        _isDeleted = (docEnded->flags & kRevDeleted) != 0;
        _isAccessRemoved = (docEnded->flags & kRevPurged) != 0;
        _c4Error = docEnded->error;
        _isTransientError = docEnded->errorIsTransient;
    }
    return self;
}


- (void) resetError {
    _c4Error = {};
}


- (NSError*) error {
    if (_c4Error.code) {
        NSError* error;
        convertError(_c4Error, &error);
        return error;
    }
    return nil;
}

@end
