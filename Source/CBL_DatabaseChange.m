//
//  CBL_DatabaseChange.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/13.
//
//

#import "CBL_DatabaseChange.h"
#import "CBL_Revision.h"


@implementation CBL_DatabaseChange


@synthesize addedRevision=_addedRevision, winningRevision=_winningRevision,
            maybeConflict=_maybeConflict, source=_source;


- (instancetype) initWithAddedRevision: (CBL_Revision*)addedRevision
                       winningRevision: (CBL_Revision*)winningRevision;
{
    self = [super init];
    if (self) {
        _addedRevision = addedRevision;
        _winningRevision = winningRevision;
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    // CBL_Revisions need to be copied because they contain mutable state:
    CBL_DatabaseChange* change =  [[[self class] alloc] initWithAddedRevision: [_addedRevision copy]
                                                         winningRevision: [_winningRevision copy]];
    change.maybeConflict = _maybeConflict;
    change.source = _source;
    return change;
}


- (BOOL) isEqual:(id)object {
    return [object isKindOfClass: [CBL_DatabaseChange class]]
        && $equal(_addedRevision, [object addedRevision])
        && $equal(_winningRevision, [object winningRevision])
        && $equal(_source, [object source]);
}


@end
