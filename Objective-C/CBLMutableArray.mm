//
//  CBLMutableArray.mm
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

#import "CBLMutableArray.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "CBLFleece.hh"


@implementation CBLMutableArray


#pragma mark - Initializers


+ (instancetype) array {
    return [[self alloc] init];
}


- (instancetype) init {
    return [super initEmpty];
}


- (instancetype) initWithData: (nullable NSArray*)data {
    self = [self init];
    if (self) {
        [self setData: data];
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    CBL_LOCK(self.sharedLock) {
        return [[CBLArray alloc] initWithCopyOfMArray: _array isMutable: false];
    }
}


#pragma mark - Type Setters


[[noreturn]] static void throwRangeException(NSUInteger index) {
    [NSException raise: NSRangeException format: @"CBLMutableArray index %lu is out of range",
        (unsigned long)index];
    abort();
}


- (void) setValue: (id)value atIndex: (NSUInteger)index {
    CBL_LOCK(self.sharedLock) {
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
}


- (void) setString: (nullable NSString*)value atIndex: (NSUInteger)index {
    [self setValue: value atIndex: index];
}


- (void) setNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index {
    [self setValue: value atIndex: index];
}


- (void) setInteger: (NSInteger)value atIndex: (NSUInteger)index {
    [self setValue: @(value) atIndex: index];
}


- (void) setLongLong: (long long)value atIndex: (NSUInteger)index {
    [self setValue: @(value) atIndex: index];
}


- (void) setFloat: (float)value atIndex: (NSUInteger)index {
    [self setValue: @(value) atIndex: index];
}


- (void) setDouble: (double)value atIndex: (NSUInteger)index {
    [self setValue: @(value) atIndex: index];
}


- (void) setBoolean: (BOOL)value atIndex: (NSUInteger)index {
    [self setValue: @(value) atIndex: index];
}


- (void) setDate: (nullable NSDate*)value atIndex: (NSUInteger)index {
    [self setValue: value atIndex: index];
}


- (void) setBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index {
    [self setValue: value atIndex: index];
}


- (void) setArray: (nullable CBLArray*)value atIndex: (NSUInteger)index {
    [self setValue: value atIndex: index];
}


- (void) setDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index {
    [self setValue: value atIndex: index];
}


#pragma mark - Type Appenders


- (void) addValue: (id)value  {
    CBL_LOCK(self.sharedLock) {
        // NOTE: nil conversion only for Apple platforms (see comment on -setValue:atIndex:)
        if (!value) value = [NSNull null];
        _array.append([value cbl_toCBLObject]);
    }
}


- (void) addString: (nullable NSString*)value {
    [self addValue: value];
}


- (void) addNumber: (nullable NSNumber*)value {
    [self addValue: value];
}


- (void) addInteger: (NSInteger)value {
    [self addValue: @(value)];
}


- (void) addLongLong: (long long)value {
    [self addValue: @(value)];
}


- (void) addFloat: (float)value {
    [self addValue: @(value)];
}


- (void) addDouble: (double)value {
    [self addValue: @(value)];
}


- (void) addBoolean: (BOOL)value {
    [self addValue: @(value)];
}


- (void) addDate: (nullable NSDate*)value {
    [self addValue: value];
}


- (void) addBlob: (nullable CBLBlob*)value {
    [self addValue: value];
}


- (void) addArray: (nullable CBLArray*)value {
    [self addValue: value];
}


- (void) addDictionary: (nullable CBLDictionary*)value {
    [self addValue: value];
}


#pragma mark - Type Inserters


- (void) insertValue: (id)value atIndex: (NSUInteger)index {
    CBL_LOCK(self.sharedLock) {
        // NOTE: nil conversion only for Apple platforms (see comment on -setValue:atIndex:)
        if (!value) value = [NSNull null];
        if (!_array.insert(index, [value cbl_toCBLObject]))
            throwRangeException(index);
    }
}


- (void) insertString: (nullable NSString*)value atIndex: (NSUInteger)index {
    [self insertValue: value atIndex: index];
}


- (void) insertNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index {
    [self insertValue: value atIndex: index];
}


- (void) insertInteger: (NSInteger)value atIndex: (NSUInteger)index {
    [self insertValue: @(value) atIndex: index];
}


- (void) insertLongLong: (long long)value atIndex: (NSUInteger)index {
    [self insertValue: @(value) atIndex: index];
}


- (void) insertFloat: (float)value atIndex: (NSUInteger)index {
    [self insertValue: @(value) atIndex: index];
}


- (void) insertDouble: (double)value atIndex: (NSUInteger)index {
    [self insertValue: @(value) atIndex: index];
}


- (void) insertBoolean: (BOOL)value atIndex: (NSUInteger)index {
    [self insertValue: @(value) atIndex: index];
}


- (void) insertDate: (nullable NSDate*)value atIndex: (NSUInteger)index {
    [self insertValue: value atIndex: index];
}


- (void) insertBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index {
    [self insertValue: value atIndex: index];
}


- (void) insertArray: (nullable CBLArray*)value atIndex: (NSUInteger)index {
    [self insertValue: value atIndex: index];
}


- (void) insertDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index {
    [self insertValue: value atIndex: index];
}


#pragma mark - Set Content with an Array


- (void) setData:(nullable NSArray *)data {
    CBL_LOCK(self.sharedLock) {
        _array.clear();
        for (id obj in data)
            _array.append([obj cbl_toCBLObject]);
    }
}


#pragma mark - Remove value


- (void) removeValueAtIndex:(NSUInteger)index {
    CBL_LOCK(self.sharedLock) {
        if (!_array.remove(index))
            throwRangeException(index);
    }
}


#pragma mark - Subscript


- (CBLMutableFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    if (index >= _array.count())
        return nil;
    return [[CBLMutableFragment alloc] initWithParent: self index: index];
}


#pragma mark - CBLConversion


- (id) cbl_toCBLObject {
    // Overrides CBLArray
    return self;
}


@end
