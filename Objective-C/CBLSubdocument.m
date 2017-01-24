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
    NSMapTable* _sharedStrings;
}


@synthesize parent=_parent;

- (BOOL) exists {
    return [_parent exists] && self.root;
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
    _sharedStrings = nil;
}


- (void) setOnMutate: (nullable CBLOnMutateBlock)onMutate {
    _onMutate = onMutate;
}


- (void) invalidate {
    self.root = NULL;
    _parent = nil;
    _onMutate = nil;
    _sharedKeys = nil;
    _sharedStrings = nil;
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
