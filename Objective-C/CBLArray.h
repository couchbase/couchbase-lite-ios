//
//  CBLArray.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArray.h"
#import "CBLArrayFragment.h"
@class CBLDictionary;
@class CBLArray;

NS_ASSUME_NONNULL_BEGIN

/** CBLArray protocol defines a set of methods for getting and setting array data. */
@protocol CBLArray <CBLReadOnlyArray, CBLArrayFragment>

/** Set an array as a content. Allowed value types are NSArray, NSDate, NSDictionary, NSNumber,
 NSNull, NSString, CBLArray, CBLBlob, CBLDictionary. The NSArrays and NSDictionaries must
 contain only the above types. Setting the new array content will replace the current data
 including the existing CBLArray and CBLDictionary objects.
 @param array  the array. */
- (void) setArray: (nullable NSArray*)array;

/** Sets an object at the given index. Setting a nil value is eqivalent to setting an NSNull object.
    @param object   the object.
    @param index    the index. This value must not exceed the bounds of the array. */
- (void) setObject: (nullable id)object atIndex: (NSUInteger)index;

/** Adds an object to the end of the array. Adding a nil value is equivalent
    to adding an NSNull object. 
    @param object   the object. */
- (void) addObject: (nullable id)object;

/** Inserts an object at the given index. Inserting a nil value is equivalent to inserting 
    an NSNull object. 
    @param object   the object.
    @param index    the index. This value must not exceed the bounds of the array. */
- (void) insertObject: (nullable id)object atIndex: (NSUInteger)index;

/** Removes the object at the given index. 
    @param index    the index. This value must not exceed the bounds of the array. */
- (void) removeObjectAtIndex: (NSUInteger)index;

/** Gets a CBLArray at the given index. Returns nil if the value is not an array.
    @param index    the index. This value must not exceed the bounds of the array. 
    @result the CBLArray object.
 */
- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index;

/** Gets a CBLDictionary at the given index. Returns nil if the value is not a dictionary.
    @param index    the index. This value must not exceed the bounds of the array. 
    @result the CBLDictionary object. */
- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index;

/** Subscripting access to a CBLFragment object that represents the value at the given index. 
    @param index    the index. If the index value exceeds the bounds of the array, 
                    the CBLFragment will represent a nil value.
    @result the CBLFragment object. */
- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end

/** CBLArray provides access to array data. */
@interface CBLArray : CBLReadOnlyArray <CBLArray>

/** Creates a new empty CBLArray object. 
    @result the CBLArray object. */
+ (instancetype) array;

/** Initialize a new empty CBLArray object. 
    @result the CBLArray object. */
- (instancetype) init;

/** Initialize a new CBLArray object with an array content. Allowed value types are NSArray, 
    NSDate, NSDictionary, NSNumber, NSNull, NSString, CBLArray, CBLBlob, CBLDictionary.
    The NSArrays and NSDictionaries must contain only the above types.
    @param array    the array object.
    @result the CBLArray object. */
- (instancetype) initWithArray: (NSArray*)array;

@end

NS_ASSUME_NONNULL_END
