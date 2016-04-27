//
//  CBLDatabaseChange.h
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

#import "CBLDatabaseChange.h"
#import "CBL_Revision.h"
#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"


@implementation CBLDatabaseChange


@synthesize documentID=_documentID, addedRevision=_addedRevision, winningRevisionID=_winningRevisionID,
            inConflict=_inConflict, source=_source, echoed=_echoed;


- (instancetype) initWithAddedRevision: (CBL_Revision*)addedRevision
                     winningRevisionID: (CBL_RevID*)winningRevisionID
                            inConflict: (BOOL)maybeConflict
                                source: (NSURL*)source
{
    Assert(addedRevision);
    Assert(addedRevision.sequence);
    self = [super init];
    if (self) {
        // Input CBL_Revisions need to be copied in case they are mutable:
        _addedRevision = addedRevision.copy;
        _documentID = _addedRevision.docID;
        _winningRevisionID = winningRevisionID;
        _inConflict = maybeConflict;
        _source = source;
    }
    return self;
}

- (instancetype) initWithPurgedDocument: (NSString*)docID {
    Assert(docID);
    self = [super init];
    if (self) {
        _documentID = docID;
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    CBLDatabaseChange* change;
    if (_addedRevision) {
        change =  [[[self class] alloc] initWithAddedRevision: _addedRevision
                                            winningRevisionID: _winningRevisionID
                                                   inConflict: _inConflict
                                                       source: _source];
    } else {
        change =  [[[self class] alloc] initWithPurgedDocument: _documentID];
    }
    change->_echoed = true; // Copied changes are echoes
    return change;
}


- (BOOL) isEqual:(id)object {
    return [object isKindOfClass: [CBLDatabaseChange class]]
        && $equal(_documentID, [object documentID])
        && $equal(_addedRevision, [object addedRevision])
        && $equal(_winningRevisionID, [object winningRevisionID])
        && $equal(_source, [object source]);
}


- (NSString*) revisionID    {return _addedRevision.revIDString;}
- (UInt64) sequenceNumber   {return _addedRevision.sequence;}
- (BOOL) isDeletion         {return _addedRevision.deleted;}

- (BOOL) isCurrentRevision {
    return _winningRevisionID && $equal(_addedRevision.revID, _winningRevisionID);
}

- (CBL_Revision*) winningRevisionIfKnown {
    return self.isCurrentRevision ? _addedRevision : nil;
}


- (NSString*) description {
    if (_addedRevision)
        return [NSString stringWithFormat: @"%@[%@]", self.class, _addedRevision];
    else
        return [NSString stringWithFormat: @"%@[purged %@]", self.class, _documentID];
}


- (void) reduceMemoryUsage {
    _addedRevision = [_addedRevision copyWithoutBody];
}


@end
