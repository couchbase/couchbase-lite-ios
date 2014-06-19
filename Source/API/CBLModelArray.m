//
//  CBLModelArray.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/12/13.
//  Copyright (c) 2013 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLModelArray.h"
#import "CBLModel_Internal.h"
#import "CBLDatabase+Insertion.h"
#import "CouchbaseLitePrivate.h"


@implementation CBLModelArray
{
    CBLModel* _owner;
    NSString* _property;
    Class _itemClass;
    NSArray* _docIDs;
}

@synthesize docIDs=_docIDs;

- (instancetype) initWithOwner: (CBLModel*)owner
                      property: (NSString*)property
                     itemClass: (Class)itemClass
                        docIDs: (NSArray*)docIDs
{
    self = [super init];
    if (self) {
        for (id item in docIDs) {
            if (![CBLDatabase isValidDocumentID: $castIf(NSString, item)]) {
                return nil;
            }
        }
        _owner = owner;
        _property = property;
        _itemClass = itemClass;
        _docIDs = [docIDs copy];
    }
    return self;
}

- (instancetype) initWithOwner: (CBLModel*)owner
                      property: (NSString*)property
                     itemClass: (Class)itemClass
                        models: (NSArray*)models
{
    NSArray* docIDs = [models my_map:^id(id obj) {
        return $cast(CBLModel, obj).document.documentID;
    }];
    return [self initWithOwner: owner property: property itemClass: itemClass docIDs: docIDs];
}

- (NSUInteger)count {
    return _docIDs.count;
}

- (id)objectAtIndex:(NSUInteger)index {
    NSString* docID = $cast(NSString, _docIDs[index]);
    //Log(@"%@<%p> objectAtIndex: %u = %@", self.class, self, (unsigned)index, docID);
    return [_owner modelWithDocID: docID forProperty: _property ofClass: _itemClass];
}

- (BOOL) isEqual:(id)object {
    // Optimization to avoid dereferencing every model when comparing two model-arrays
    if (![object isKindOfClass: [CBLModelArray class]])
        return [super isEqual: object];
    CBLModelArray* other = object;
    return other->_owner.database == _owner.database
        && [other->_docIDs isEqual: _docIDs];
}

- (NSString*) description {
    return $sprintf(@"%@<%@>{%@}",
                    [self class], _itemClass, [_docIDs componentsJoinedByString: @", "]);
}

- (NSString*) debugDescription {
    return self.description;
}

@end
