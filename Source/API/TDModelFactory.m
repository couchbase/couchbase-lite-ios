//
//  TouchModelFactory.m
//  TouchDB
//
//  Created by Jens Alfke on 11/22/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDModelFactory.h"
#import "TDModel.h"
#import "TouchDBPrivate.h"


@implementation TDModelFactory


static TDModelFactory* sSharedInstance;


+ (TDModelFactory*) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sSharedInstance = [[self alloc] init];
    });
    return sSharedInstance;
}


- (id)init {
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
        NSAssert(klass, @"TouchModelFactory: no class named %@", className);
    }
    return klass;
}


- (Class) classForDocument: (TDDocument*)document {
    NSString* type = [document propertyForKey: @"type"];
    return type ? [self classForDocumentType: type] : nil;
}


- (id) modelForDocument: (TDDocument*)document {
    TDModel* model = document.modelObject;
    if (model)
        return model;
    return [[self classForDocument: document] modelForDocument: document];
}


@end




@implementation TDDatabase (TouchModelFactory)

- (TDModelFactory*) modelFactory {
    if (!_modelFactory)
        _modelFactory = [[TDModelFactory alloc] init];
    return _modelFactory;
}

- (void) setModelFactory:(TDModelFactory *)modelFactory {
    _modelFactory = modelFactory;
}

@end