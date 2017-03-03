//
//  CBLSubdocument.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLSubdocument.h"
#import "CBLSubdocument+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLDocument.h"
#import "CBLInternal.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"


@implementation CBLSubdocument {
    CBLOnMutateBlock _onMutate;
}


@synthesize parent=_parent, key=_key, swiftSubdocument=_swiftSubdocument;


- (instancetype) init {
    return [super initWithSharedKeys: cbl::SharedKeys()];
}


+ (instancetype) subdocument {
    return [[CBLSubdocument alloc] init];
}


- (instancetype) copyWithZone:(NSZone *)zone {
    CBLSubdocument* o = [[self.class alloc] init];
    o.properties = self.properties;
    return o;
}


- (nullable CBLDocument*) document {
    id p = _parent; // strong parent
    return [p isKindOfClass: [CBLDocument class]] ? p : [p parent];
}


- (BOOL) exists {
    return [self hasRoot];
}


#pragma mark - CBLProperties


- (CBLBlob*) blobWithProperties: (NSDictionary*) properties error: (NSError **)error {
    CBLDocument* doc = self.document;
    if (doc)
        return [[CBLBlob alloc] initWithDatabase: doc.database properties: properties error: error];
    else {
        // TODO: Create CBL Error:
        CBLWarn(Database, @"Cannot read blob from the subdocument not attached to a document.");
        return nil;
    }
}


- (BOOL) storeBlob: (CBLBlob*)blob error: (NSError**)error {
    CBLDocument* doc = self.document;
    if (doc)
        return [blob installInDatabase: doc.database error: error];
    else {
        // TODO: Create CBL Error:
        CBLWarn(Database, @"Cannot store blob inside the subdocument not attached to a document.");
        return NO;
    }
}


- (void) setHasChanges: (BOOL)hasChanges {
    if (self.hasChanges != hasChanges) {
        [super setHasChanges: hasChanges];
        if (_onMutate)
            _onMutate();
    }
}


#pragma mark - INTERNAL


- (instancetype) initWithParent: (nullable CBLProperties*)parent
                     sharedKeys: (cbl::SharedKeys)sharedKeys
{
    self = [super initWithSharedKeys: sharedKeys];
    if (self) {
        self.parent = parent;
    }
    return self;
}


- (void) setOnMutate: (nullable CBLOnMutateBlock)onMutate {
    _onMutate = onMutate;
}


- (void) invalidate {
    self.parent = nil;
    [self setOnMutate: nil];
    [self setRootDict: nil];
    self.properties = nil;
    [self resetChangesKeys];
}


- (NSDictionary*) jsonRepresentation {
    return self.properties ?: @{};
}


@end
