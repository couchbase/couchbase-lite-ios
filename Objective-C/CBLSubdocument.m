//
//  CBLSubdocument.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLSubdocument.h"
#import "CBLInternal.h"


@implementation CBLSubdocument {
    __weak id _parent;
    CBLOnMutateBlock _onMutate;
    FLSharedKeys _sharedKeys;
}


@synthesize parent=_parent;

+ (instancetype) subdocument {
    return [[[self class] alloc] init];
}


- (nullable CBLDocument*) document {
    if (!_parent)
        return nil;
    
    id strongParent = _parent;
    if ([strongParent isKindOfClass: [CBLDocument class]])
        return strongParent;
    else
        return [strongParent parent];
}


- (BOOL) exists {
    return [self.document exists];
}

#pragma mark - INTERNAL


- (instancetype) initWithParent: (id)parent root: (nullable FLDict)root {
    self = [super init];
    if (self) {
        _parent = parent;
        self.root = root;
    }
    return self;
}


- (void) setParent: (id)parent {
    if (_parent != parent)
        _parent = parent;
    _sharedKeys = nil;
}


- (void) setOnMutate: (nullable CBLOnMutateBlock)onMutate {
    _onMutate = onMutate;
}


- (void) invalidate {
    self.root = NULL;
    _parent = nil;
    _onMutate = nil;
    _sharedKeys = nil;
}


- (id) encodeAsJSON {
    id obj = [super encodeAsJSON];
    return obj ? obj : @{};
}


#pragma mark - CBLProperties


- (void) setHasChanges: (BOOL)hasChanges {
    if (self.hasChanges != hasChanges) {
        [super setHasChanges: hasChanges];
        if (_onMutate)
            _onMutate();
    }
}


- (FLSharedKeys) sharedKeys {
    if (!_sharedKeys)
        _sharedKeys = [_parent sharedKeys];
    return _sharedKeys;
}


@end
