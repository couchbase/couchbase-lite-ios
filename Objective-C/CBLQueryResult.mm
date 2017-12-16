//
//  CBLQueryResult.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/18/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
using namespace fleeceapi;


@implementation CBLQueryResult {
    CBLQueryResultSet* _rs;
    FLArrayIterator _columns;
    MContext* _context;
}


- (instancetype) initWithResultSet: (CBLQueryResultSet*)rs
                      c4Enumerator: (C4QueryEnumerator*)e
                           context: (MContext*)context
{
    self = [super init];
    if (self) {
        _rs = rs;
        _columns = e->columns;
        _context = context;
    }
    return self;
}


#pragma mark - CBLArray


- (NSUInteger) count {
    // TODO: We should make it strong reference instead:
    // https://github.com/couchbase/couchbase-lite-ios/issues/1983
    CBLDatabase* db = _rs.database;
    CBL_LOCK(db) {
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
    FLSharedKeys sk = [self database].sharedKeys;
    
    NSMutableArray* array = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.count; i++) {
        [array addObject: FLValue_GetNSObject([self fleeceValueAtIndex: i], sk, nullptr)];
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
    return index > 0;
}


- (NSDictionary<NSString*,id>*) toDictionary {
    NSArray* values = [self toArray];
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    for (NSString* name in _rs.columnNames) {
        NSInteger index = [self indexForColumnName: name];
        dict[name] = values[index];
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


- (CBLDatabase*) database {
    CBLDatabase* database = _rs.database;
    Assert(database);
    return database;
}


- (NSInteger) indexForColumnName: (NSString*)name {
    NSNumber* index = [_rs.columnNames objectForKey: name];
    return index ? index.integerValue : -1;
}


- (id) fleeceValueToObjectAtIndex: (NSUInteger)index {
    FLValue value = [self fleeceValueAtIndex: index];
    if (value == nullptr)
        return nil;
    MRoot<id> root(_context, value, false);
    return root.asNative();
}


- (FLValue) fleeceValueAtIndex: (NSUInteger)index {
    return FLArrayIterator_GetValueAt(&_columns, (uint32_t)index);
}


@end
