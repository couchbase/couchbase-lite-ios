//
//  CBL_DatabaseChange.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_DatabaseChange.h"
#import "CBL_Revision.h"


@implementation CBL_DatabaseChange


@synthesize addedRevision=_addedRevision, winningRevision=_winningRevision,
            maybeConflict=_maybeConflict, source=_source, echoed=_echoed;


- (instancetype) initWithAddedRevision: (CBL_Revision*)addedRevision
                       winningRevision: (CBL_Revision*)winningRevision;
{
    self = [super init];
    if (self) {
        // Input CBL_Revisions need to be copied in case they are mutable:
        _addedRevision = addedRevision.copy;
        _winningRevision = winningRevision.copy;
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    CBL_DatabaseChange* change =  [[[self class] alloc] initWithAddedRevision: _addedRevision
                                                              winningRevision: _winningRevision];
    change->_maybeConflict = _maybeConflict;
    change->_source = _source;
    change->_echoed = true; // Copied changes are echoes
    return change;
}


- (BOOL) isEqual:(id)object {
    return [object isKindOfClass: [CBL_DatabaseChange class]]
        && $equal(_addedRevision, [object addedRevision])
        && $equal(_winningRevision, [object winningRevision])
        && $equal(_source, [object source]);
}


@end
