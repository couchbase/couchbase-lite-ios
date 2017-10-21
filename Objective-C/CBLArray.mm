//
//  CBLArray.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLArray.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "CBLFleece.hh"


@implementation CBLArray


#pragma mark - Initializers


+ (instancetype) array {
    return [[self alloc] init];
}


- (instancetype) init {
    return [super initEmpty];
}


- (instancetype) initWithArray: (NSArray*)array {
    self = [self init];
    if (self) {
        [self setArray: array];
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    return [[CBLReadOnlyArray alloc] initWithCopyOfMArray: _array isMutable: false];
}


#pragma mark - Type Setters


[[noreturn]] static void throwRangeException(NSUInteger index) {
    [NSException raise: NSRangeException format: @"CBLArray index %lu is out of range",
        (unsigned long)index];
    abort();
}


- (void) setObject: (id)value atIndex: (NSUInteger)index {
    // NOTE: Java and C# allow storing a null value in an array; this gets saved in the document as
    // a JSON "null". But Cocoa doesn't allow this and throws an exception.
    // For cross-platform consistency we're allowing nil values on Apple platforms too,
    // by translating them to an NSNull so they have the same behavior in the document.
    if (!value) value = [NSNull null];

    if (cbl::valueWouldChange(value, _array.get(index), _array)) {
        if (!_array.set(index, [value cbl_toCBLObject]))
            throwRangeException(index);
    }
}


- (void) setArray: (nullable CBLArray*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setBoolean: (BOOL)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setDate: (nullable NSDate*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setDouble: (double)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setFloat: (float)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setInteger: (NSInteger)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setLongLong: (long long)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setString: (nullable NSString*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


#pragma mark - Type Appenders


- (void) addObject: (id)value  {
    // NOTE: nil conversion only for Apple platforms (see comment on -setObject:atIndex:)
    if (!value) value = [NSNull null];
    _array.append([value cbl_toCBLObject]);
}


- (void) addArray: (nullable CBLArray*)value {
    [self addObject: value];
}


- (void) addBlob: (nullable CBLBlob*)value {
    [self addObject: value];
}


- (void) addBoolean: (BOOL)value {
    [self addObject: @(value)];
}


- (void) addDate: (nullable NSDate*)value {
    [self addObject: value];
}


- (void) addDictionary: (nullable CBLDictionary*)value {
    [self addObject: value];
}


- (void) addDouble: (double)value {
    [self addObject: @(value)];
}


- (void) addFloat: (float)value {
    [self addObject: @(value)];
}


- (void) addInteger: (NSInteger)value {
    [self addObject: @(value)];
}


- (void) addLongLong: (long long)value {
    [self addObject: @(value)];
}


- (void) addNumber: (nullable NSNumber*)value {
    [self addObject: value];
}


- (void) addString: (nullable NSString*)value {
    [self addObject: value];
}


#pragma mark - Type Inserters


- (void) insertObject: (id)value atIndex: (NSUInteger)index {
    // NOTE: nil conversion only for Apple platforms (see comment on -setObject:atIndex:)
    if (!value) value = [NSNull null];
    if (!_array.insert(index, [value cbl_toCBLObject]))
        throwRangeException(index);
}


- (void) insertArray: (nullable CBLArray*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertBoolean: (BOOL)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertDate: (nullable NSDate*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertDouble: (double)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertFloat: (float)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertInteger: (NSInteger)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertLongLong: (long long)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertString: (nullable NSString*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


#pragma mark - Set Content with an Array


- (void) setArray:(nullable NSArray *)array {
    _array.clear();
    for (id obj in array)
        _array.append([obj cbl_toCBLObject]);
}


#pragma mark - Remove value


- (void) removeObjectAtIndex:(NSUInteger)index {
    if (!_array.remove(index))
        throwRangeException(index);
}


#pragma mark - Subscript


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    if (index >= _array.count())
        return nil;
    return [[CBLFragment alloc] initWithParent: self index: index];
}


#pragma mark - CBLConversion


- (id) cbl_toCBLObject {
    // Overrides CBLReadOnlyArray
    return self;
}


@end
