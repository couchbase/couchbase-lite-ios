//
//  TouchModelFactory.m
//  TouchDB
//
//  Created by Jens Alfke on 11/22/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TouchModelFactory.h"
#import "TouchModel.h"
#import "TouchDBPrivate.h"


@implementation TouchModelFactory


static TouchModelFactory* sSharedInstance;


+ (TouchModelFactory*) sharedInstance {
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


- (void)dealloc {
    [_typeDict release];
    [super dealloc];
}


- (void) registerClass: (id)classOrName forDocumentType: (NSString*)type {
    [_typeDict setValue: classOrName forKey: type];
}


- (Class) classForDocumentType: (NSString*)type {
    id klass = [_typeDict objectForKey: type];
    if (!klass && self != sSharedInstance)
        return [sSharedInstance classForDocumentType: type];
    if ([klass isKindOfClass: [NSString class]]) {
        NSString* className = klass;
        klass = NSClassFromString(className);
        NSAssert(klass, @"TouchModelFactory: no class named %@", className);
    }
    return klass;
}


- (Class) classForDocument: (TouchDocument*)document {
    NSString* type = [document propertyForKey: @"type"];
    return type ? [self classForDocumentType: type] : nil;
}


- (id) modelForDocument: (TouchDocument*)document {
    TouchModel* model = document.modelObject;
    if (model)
        return model;
    return [[self classForDocument: document] modelForDocument: document];
}


@end




@implementation TouchDatabase (TouchModelFactory)

- (TouchModelFactory*) modelFactory {
    if (!_modelFactory)
        _modelFactory = [[TouchModelFactory alloc] init];
    return _modelFactory;
}

- (void) setModelFactory:(TouchModelFactory *)modelFactory {
    [_modelFactory autorelease];
    _modelFactory = [modelFactory retain];
}

@end