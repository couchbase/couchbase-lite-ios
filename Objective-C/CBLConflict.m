//
//  CBLConflict.m
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

#import "CBLConflict+Internal.h"

@implementation CBLConflict

@synthesize documentID=_documentID, localDocument=_localDocument, remoteDocument=_remoteDocument;

# pragma mark - Internal

- (instancetype) initWithID: (NSString*)documentID
              localDocument: (CBLDocument*)localDoc
             remoteDocument: (CBLDocument*)remoteDoc {
    Assert(localDoc != nil || remoteDoc != nil, @"Local and remote document shouldn't be empty \
           at same time, when resolving conflict.");
    self = [super init];
    if (self) {
        _documentID = documentID;
        _localDocument = localDoc;
        _remoteDocument = remoteDoc;
    }
    return self;
}

@end
