//
//  CBLModelFactory.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/22/11.
//  Copyright (c) 2011-2013 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLModelFactory.h"
#import "CBLModel.h"
#import "CouchbaseLitePrivate.h"


@implementation CBLModelFactory
{
    NSMutableDictionary* _typeDict;
    NSMutableDictionary* _queryBuilders;
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

- (NSArray*) documentTypesForClass: (Class)modelClass {
    NSArray *keys = [_typeDict allKeysForObject:modelClass];
    if (keys.count == 0)
        keys = [_typeDict allKeysForObject: NSStringFromClass(modelClass)];
    return keys;
}

- (NSString*) documentTypeForClass: (Class)modelClass {
    NSArray *keys = [self documentTypesForClass: modelClass];
    return keys.count == 1 ? keys.firstObject : nil;
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


- (void) setQueryBuilder: (CBLQueryBuilder*)builder
                forClass: (Class)klass
                property: (NSString*)property
{
    id key = [[NSArray alloc] initWithObjects: property, klass, nil];  // klass might be nil
    if (!_queryBuilders)
        _queryBuilders = [[NSMutableDictionary alloc] init];
    _queryBuilders[key] = builder;
}

- (CBLQueryBuilder*) queryBuilderForClass: (Class)klass
                                 property: (NSString*)property
{
    id key = [[NSArray alloc] initWithObjects: property, klass, nil];  // klass might be nil
    return _queryBuilders[key];
}



@end
