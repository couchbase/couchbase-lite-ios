//
//  TD_DatabaseChange.h
//  TouchDB
//
//  Created by Jens Alfke on 1/18/13.
//
//

#import "TD_DatabaseChange.h"
#import "TD_Revision.h"


@implementation TD_DatabaseChange


@synthesize addedRevision=_addedRevision, winningRevision=_winningRevision,
            maybeConflict=_maybeConflict, source=_source;


- (id) initWithAddedRevision: (TD_Revision*)addedRevision
             winningRevision: (TD_Revision*)winningRevision;
{
    self = [super init];
    if (self) {
        _addedRevision = addedRevision;
        _winningRevision = winningRevision;
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    // TD_Revisions need to be copied because they contain mutable state:
    TD_DatabaseChange* change =  [[[self class] alloc] initWithAddedRevision: [_addedRevision copy]
                                                         winningRevision: [_winningRevision copy]];
    change.maybeConflict = _maybeConflict;
    change.source = _source;
    return change;
}


- (BOOL) isEqual:(id)object {
    return [object isKindOfClass: [TD_DatabaseChange class]]
        && $equal(_addedRevision, [object addedRevision])
        && $equal(_winningRevision, [object winningRevision])
        && $equal(_source, [object source]);
}


@end
