//
//  CBLFleeceArray.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFleeceArray.h"
#import "CBLFleeceDictionary.h"
#import "CBLC4Document.h"
#import "CBLDocument+Internal.h"
#import "CBLDatabase.h"
#import "CBLInternal.h"
#import "CBLJSON.h"
#import "CBLReadOnlySubdocument.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"


@implementation CBLFleeceArray {
    FLArray _array;
    CBLC4Document* _document;
    CBLDatabase* _database;
    cbl::SharedKeys _sharedKeys;
}


- (instancetype) initWithArray: (FLArray) array
                      document: (CBLC4Document*)document
                      database: (CBLDatabase*)database
{
    self = [super init];
    if (self) {
        _array = array;
        _document = document;
        _database = database;
        _sharedKeys = _database.sharedKeys;
    }
    return self;
}


+ (instancetype) withArray:(FLArray)array
                  document:(CBLC4Document *)document
                  database:(CBLDatabase *)database
{
    return [[self alloc] initWithArray: array document: document database: database];
}


+ (instancetype) empty {
    return [[self alloc] init];
}


- (id <CBLReadOnlyArray>) data {
    return self;
}


- (id) documentData {
    return _document;
}


- (nullable id) objectAtIndex: (NSUInteger)index {
    return [self fleeceValueToObject: [self fleeceValueForIndex: index]];
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    return FLValue_AsBool([self fleeceValueForIndex: index]);
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    return (NSInteger)FLValue_AsInt([self fleeceValueForIndex: index]);
}


- (float) floatAtIndex: (NSUInteger)index {
    return FLValue_AsFloat([self fleeceValueForIndex: index]);
}


- (double) doubleAtIndex: (NSUInteger)index {
    return FLValue_AsDouble([self fleeceValueForIndex: index]);
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    return $castIf(NSString, [self objectAtIndex: index]);
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    return $castIf(NSNumber, [self objectAtIndex: index]);
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return [CBLJSON dateWithJSONObject: [self stringAtIndex: index]];
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    return $castIf(CBLBlob, [self objectAtIndex: index]);
}


- (nullable CBLReadOnlySubdocument*) subdocumentAtIndex: (NSUInteger)index {
    return $castIf(CBLReadOnlySubdocument, [self objectAtIndex: index]);
}


- (nullable CBLReadOnlyArray*) arrayAtIndex: (NSUInteger)index {
    return $castIf(CBLReadOnlyArray, [self objectAtIndex: index]);
}


- (NSUInteger) count {
    return FLArray_Count(_array);
}


- (NSArray*) toArray {
    NSMutableArray* array = [NSMutableArray arrayWithCapacity: self.count];
    for (NSUInteger i = 0; i < self.count; i++) {
        FLValue value = [self fleeceValueForIndex: i];
        [array addObject: FLValue_GetNSObject(value, &_sharedKeys)];
    }
    return array;
}


#pragma mark - FLEECE


- (CBLFleeceArray*) fleeceArray: (FLArray)array {
    return [CBLFleeceArray withArray: array document: _document database: _database];
}


- (CBLFleeceDictionary*) fleeceDictionary: (FLDict)dict {
    return [CBLFleeceDictionary withDict: dict document: _document database: _database];
}


- (FLValue) fleeceValueForIndex: (NSUInteger)index {
    return FLArray_Get(_array, (uint)index);
}


- (id) fleeceValueToObject: (FLValue)value {
    switch (FLValue_GetType(value)) {
        case kFLArray: {
            FLArray array = FLValue_AsArray(value);
            id data = [self fleeceArray: array];
            return [[CBLReadOnlyArray alloc] initWithData: data];
        }
        case kFLDict: {
            FLDict dict = FLValue_AsDict(value);
            FLSlice type = [self dictionaryType: dict];
            if(!type.buf) {
                id data = [self fleeceDictionary: dict];
                return [[CBLReadOnlySubdocument alloc] initWithData: data];
            } else {
                id result = FLValue_GetNSObject(value, &_sharedKeys);
                return [self dictionaryToObject: result];
            }
        }
        case kFLUndefined:
            return nil;
        default:
            return FLValue_GetNSObject(value, &_sharedKeys);
    }
}


- (FLSlice) dictionaryType: (FLDict)dict {
    FLSlice typeKey = FLSTR("_cbltype");
    FLValue type = FLDict_GetSharedKey(dict, typeKey, &_sharedKeys);
    return FLValue_AsString(type);
}


- (id) dictionaryToObject: (NSDictionary*)dict {
    NSString* type = dict[@"_cbltype"];
    if (type) {
        if ([type isEqualToString: @"blob"])
            return [[CBLBlob alloc] initWithDatabase: _database properties: dict];
    }
    return nil; // Invalid!
}


- (NSArray*) fleeceRootToArray: (FLArray)root  {
    if (root == nullptr)
        return nil;
    
    FLArrayIterator iter;
    FLArrayIterator_Begin(root, &iter);
    auto result = [[NSMutableArray alloc] initWithCapacity: FLArray_Count(root)];
    FLValue item;
    while (nullptr != (item = FLArrayIterator_GetValue(&iter))) {
        [result addObject: [self fleeceValueToObject: item]];
        FLArrayIterator_Next(&iter);
    }
    return result;
}


@end
