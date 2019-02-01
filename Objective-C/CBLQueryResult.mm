//
//  CBLQueryResult.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLQueryResult.h"
#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "CBLPropertyExpression.h"
#import "CBLQueryResultSet+Internal.h"
#import "MRoot.hh"


using namespace cbl;
using namespace fleece;


@implementation CBLQueryResult {
    CBLQueryResultSet* _rs;
    MContext* _context;
    NSArray<NSValue*>* _values;
    uint64_t _missingColumns;
}


- (instancetype) initWithResultSet: (CBLQueryResultSet*)rs
                      c4Enumerator: (C4QueryEnumerator*)e
                           context: (MContext*)context
{
    self = [super init];
    if (self) {
        _rs = rs;
        _context = context;
        _values = [self extractColumns: e->columns];
        _missingColumns = e->missingColumns;
    }
    return self;
}


#pragma mark - CBLArray


- (NSUInteger) count {
    CBL_LOCK(_rs.database) {
        return c4query_columnCount(_rs.c4Query);
    }
}


- (nullable id) valueAtIndex: (NSUInteger)index {
    return [self fleeceValueToObjectAtIndex: index];
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    return asString([self fleeceValueToObjectAtIndex: index]);
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    return asNumber([self fleeceValueToObjectAtIndex: index]);
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    return (NSInteger)FLValue_AsInt([self fleeceValueAtIndex: index]);
}


- (long long) longLongAtIndex: (NSUInteger)index {
    return FLValue_AsInt([self fleeceValueAtIndex: index]);
}


- (float) floatAtIndex: (NSUInteger)index {
    return FLValue_AsFloat([self fleeceValueAtIndex: index]);
}

- (double) doubleAtIndex: (NSUInteger)index {
    return FLValue_AsDouble([self fleeceValueAtIndex: index]);
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    return FLValue_AsBool([self fleeceValueAtIndex: index]);
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return asDate([self fleeceValueToObjectAtIndex: index]);
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    return $castIf(CBLBlob, [self fleeceValueToObjectAtIndex: index]);
}


- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index {
    return $castIf(CBLArray, [self fleeceValueToObjectAtIndex: index]);
}


- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index {
    return $castIf(CBLDictionary, [self fleeceValueToObjectAtIndex: index]);
}


- (NSArray*) toArray {
    NSMutableArray* array = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.count; i++) {
        id obj = [[self fleeceValueToObjectAtIndex: i] cbl_toPlainObject];
        [array addObject: obj ? obj : [NSNull null]];
    }
    return array;
}


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    if (index >= self.count)
        return nil;
    return [[CBLFragment alloc] initWithParent: self index: index];
}


#pragma mark - CBLDictionary


- (NSArray*) keys {
    // TODO: Support SELECT *
    return [_rs.columnNames allKeys];
}


- (nullable id) valueForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self valueAtIndex: index];
    return nil;
}


- (nullable NSString*) stringForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self stringAtIndex: index];
    return nil;
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self numberAtIndex: index];
    return nil;
}


- (NSInteger) integerForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self integerAtIndex: index];
    return 0;
}


- (long long) longLongForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self longLongAtIndex: index];
    return 0;
}


- (float) floatForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self floatAtIndex: index];
    return 0.0f;
}


- (double) doubleForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self doubleAtIndex: index];
    return 0.0;
}


- (BOOL) booleanForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self booleanAtIndex: index];
    return NO;
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self dateAtIndex: index];
    return nil;
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self blobAtIndex: index];
    return nil;
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self arrayAtIndex: index];
    return nil;
}


- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    if (index >= 0)
        return [self dictionaryAtIndex: index];
    return nil;
}


- (BOOL) containsValueForKey: (NSString*)key {
    NSInteger index = [self indexForColumnName: key];
    return index >= 0;
}


- (NSDictionary<NSString*,id>*) toDictionary {
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    for (NSString* name in _rs.columnNames) {
        NSInteger index = [self indexForColumnName: name];
        if (index >= 0) {
            id value = [[self valueAtIndex: index] cbl_toPlainObject];
            dict[name] = value ? value : [NSNull null];
        }
    }
    return dict;
}


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    return [self objectAtIndexedSubscript: [self indexForColumnName: key]];
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    return [_rs.columnNames countByEnumeratingWithState: state objects: buffer count: len];
}


#pragma mark - Private


- (NSArray*) extractColumns: (FLArrayIterator)columns {
    NSUInteger count = _rs.columnNames.count;
    NSMutableArray* values = [NSMutableArray arrayWithCapacity: count];
    for (uint i = 0; i < count; i++) {
        FLValue value = FLArrayIterator_GetValueAt(&columns, (uint32_t)i);
        values[i] = [NSValue valueWithPointer: value];
    }
    return values;
}


- (NSInteger) indexForColumnName: (NSString*)name {
    CBLAssertNotNil(name);
    
    NSNumber* colIndex = [_rs.columnNames objectForKey: name];
    if (!colIndex)
        return -1;
    
    NSInteger index =  colIndex.integerValue;
    BOOL hasValue = (_missingColumns & (1 << index)) == 0;
    return hasValue ? index : -1;
}


- (id) fleeceValueToObjectAtIndex: (NSUInteger)index {
    FLValue value = [self fleeceValueAtIndex: index];
    if (value == nullptr || FLValue_GetType(value) == kFLNull)
        return nil;
    
    CBL_LOCK(_rs.database) {
        MRoot<id> root(_context, value, false);
        return root.asNative();
    }
}


- (FLValue) fleeceValueAtIndex: (NSUInteger)index {
    NSUInteger count = _rs.columnNames.count;
    if (index >= count)
        [NSException raise: NSRangeException
                    format: @"index %lu beyond bounds of %lu selected keys.",
                            (unsigned long)index, (unsigned long)count];
    return (FLValue)[[_values objectAtIndex: index] pointerValue];
}


@end
