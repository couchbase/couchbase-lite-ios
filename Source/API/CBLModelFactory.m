//
//  CBLModelFactory.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/22/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "CBLModelFactory.h"
#import "CBLModel.h"
#import "CouchbaseLitePrivate.h"


@implementation CBLModelFactory
{
    NSMutableDictionary* _typeDict;
}


static CBLModelFactory* sSharedInstance;


+ (instancetype) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sSharedInstance = [[self alloc] init];
    });
    return sSharedInstance;
}


- (instancetype) init {
    self = [super init];
    if (self) {
        _typeDict = [[NSMutableDictionary alloc] init];
    }
    return self;
}


- (void) registerClass: (id)classOrName forDocumentType: (NSString*)type {
    [_typeDict setValue: classOrName forKey: type];
}


- (Class) classForDocumentType: (NSString*)type {
    id klass = _typeDict[type];
    if (!klass && self != sSharedInstance)
        return [sSharedInstance classForDocumentType: type];
    if ([klass isKindOfClass: [NSString class]]) {
        NSString* className = klass;
        klass = NSClassFromString(className);
        NSAssert(klass, @"CBLModelFactory: no class named %@", className);
    }
    return klass;
}


- (Class) classForDocument: (CBLDocument*)document {
    NSString* type = [document propertyForKey: @"type"];
    return type ? [self classForDocumentType: type] : nil;
}


- (id) modelForDocument: (CBLDocument*)document {
    CBLModel* model = document.modelObject;
    if (model)
        return model;
    return [[self classForDocument: document] modelForDocument: document];
}


@end
