//
//  CBLConflictResolver.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLConflictResolver.h"
#import "CBLReadOnlyDocument.h"

@implementation CBLConflict

@synthesize operationType=_operartionType;
@synthesize source=_source, target=_target, commonAncestor=_commonAncestor;


- (instancetype) initWithSource: (CBLReadOnlyDocument*)source
                         target: (CBLReadOnlyDocument*)target
                 commonAncestor: (CBLReadOnlyDocument*)commonAncestor
                  operationType: (CBLOperationType)operationType
{
    self = [super init];
    if (self) {
        _source = source;
        _target = target;
        _commonAncestor = commonAncestor;
        _operartionType = operationType;
    }
    return self;
}

@end
