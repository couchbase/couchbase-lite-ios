//
//  CBLModel+Properties.m
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

#import "CBLModel_Internal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLModelArray.h"
#import "CBLBase64.h"
#import "CBLJSON.h"

#import <objc/message.h>


// A type of block that converts an input value to an output value, or nil if it can't.
typedef id (^ValueConverter)(id input);


// Returns a block that will convert an input JSON value to an instance of the desired class,
// or nil if the class isn't supported.
static ValueConverter valueConverterToClass(Class toClass) {
    if (toClass == [NSData class]) {
        return ^id(id rawValue) {
            if ([rawValue isKindOfClass: [NSString class]])
                return [CBLBase64 decode: rawValue];
            return nil;
        };
    } else if (toClass == [NSDate class]) {
        return ^id(id rawValue) {
            return [CBLJSON dateWithJSONObject: rawValue];
        };
    } else if (toClass == [NSDecimalNumber class]) {
        return ^id(id rawValue) {
            if ([rawValue isKindOfClass: [NSString class]])
                return [NSDecimalNumber decimalNumberWithString: rawValue];
            return nil;
        };
    } else if ([toClass conformsToProtocol: @protocol(CBLJSONEncoding)]) {
        return ^id(id rawValue) {
            return [(id<CBLJSONEncoding>)[toClass alloc] initWIthJSON: rawValue];
        };
    } else {
        return nil;
    }
}


// Returns a block that converts the items of an array using the given ValueConverter.
static ValueConverter arrayValueConverter(ValueConverter itemConverter) {
    return ^id(id rawValue) {
        return [$castIf(NSArray, rawValue) my_map: itemConverter];
    };
}


@implementation CBLModel (Properties)


// Generic getter for a value-converted property.
- (NSData*) getProperty: (NSString*)property withConverter: (ValueConverter)converter {
    NSData* value = _properties[property];
    if (!value && !_isNew && ![_changedNames containsObject: property]) { // see -getValueOfProperty:
        id rawValue = [_document propertyForKey: property];
        value = converter(rawValue);
        if (value)
            [self cacheValue: value ofProperty: property changed: NO];
        else if (rawValue)
            Warn(@"Unable to decode property %@ of %@", property, _document);
    }
    return value;
}


#pragma mark - MODEL-VALUED PROPERTIES:


// Gets the value of a model-valued property.
- (CBLModel*) getModelProperty: (NSString*)property {
    // NOTE: Model-valued properties are kept in raw form as document IDs, not mapped to CBLModel
    // references, to avoid reference cycles.

    // First get the target document ID:
    NSString* rawValue = [self getValueOfProperty: property];
    if (!rawValue)
        return nil;

    // Look up the CBLDocument:
    if (![rawValue isKindOfClass: [NSString class]]) {
        Warn(@"Model-valued property %@ of %@ is not a string", property, _document);
        return nil;
    }

    return [self modelWithDocID: rawValue forProperty: property ofClass: Nil];
}


// Sets the value of a model-valued property.
- (void) setModel: (CBLModel*)model forProperty: (NSString*)property {
    // Don't store the target CBLModel in the _properties dictionary, because this could create
    // a reference cycle. Instead, just store the raw document ID. getModelProperty will map to the
    // model object when called.
    NSString* docID = model.document.documentID;
    NSAssert(docID || !model,
             @"Cannot assign untitled %@ as the value of model property %@.%@ -- save it first",
             model.document, [self class], property);
    [self setValue: docID ofProperty: property];
}


#pragma mark - RELATIONS (MODEL-ARRAY-VALUED PROPERTIES):


// Gets the value of a model-valued array property.
- (NSArray*) getArrayRelationProperty: (NSString*)property
                       withModelClass: (Class)modelClass
{
    // A transformed value is cached, as with -getProperty:withConverter:, except the value is a
    // CBLModelArray object, which takes a little more work to create.
    NSArray* value = _properties[property];
    if (!value) {
        id rawValue = [_document propertyForKey: property];
        if ([rawValue isKindOfClass: [NSArray class]]) {
            value = [[CBLModelArray alloc] initWithOwner: self
                                                property: property
                                               itemClass: modelClass
                                                  docIDs: rawValue];
            if (!value) {
                Warn(@"To-many relation property %@ of %@ contains invalid doc IDs: %@",
                     property, self, rawValue);
            }
        }
        if (value)
            [self cacheValue: value ofProperty: property changed: NO];
        else if (rawValue)
            Warn(@"Unable to decode array relation from property %@ of %@", property, _document);
    }
    return value;
}


// Sets the value of a model-valued array property.
- (void) setArray: (NSArray*)array
      forProperty: (NSString*)property
     ofModelClass: (Class)relClass
{
    CBLModelArray* docIDs = nil;
    if ([array isKindOfClass: [CBLModelArray class]])
        docIDs = (CBLModelArray*)array;
    else if (array != nil)
        docIDs = [[CBLModelArray alloc] initWithOwner: self
                                             property: property
                                            itemClass: relClass
                                               models: array];
    [self setValue: docIDs ofProperty: property];
}


#pragma mark - DYNAMIC METHOD GENERATORS:


// Generates a method for a property getter.
+ (IMP) impForGetterOfProperty: (NSString*)property ofClass: (Class)propertyClass {
    id (^impBlock)(CBLModel*) = nil;
    
    if (propertyClass == Nil || propertyClass == [NSString class]
             || propertyClass == [NSNumber class]
             || propertyClass == [NSDictionary class]) {
        // Basic classes (including 'id')
        return [super impForGetterOfProperty: property ofClass: propertyClass];
    } else if (propertyClass == [NSArray class]) {
        Class itemClass = [self itemClassForArrayProperty: property];
        if (itemClass == nil) {
            // Untyped array:
            return [super impForGetterOfProperty: property ofClass: propertyClass];
        } else if ([itemClass isSubclassOfClass: [CBLModel class]]) {
            // Array of models (a to-many relation):
            impBlock = ^id(CBLModel* receiver) {
                return [receiver getArrayRelationProperty: property withModelClass: itemClass];
            };
        } else {
            // Typed array of scalar class:
            ValueConverter itemConverter = valueConverterToClass(itemClass);
            if (itemConverter) {
                ValueConverter converter = arrayValueConverter(itemConverter);
                impBlock = ^id(CBLModel* receiver) {
                    return [receiver getProperty: property withConverter: converter];
                };
            }
        }
    } else if ([propertyClass isSubclassOfClass: [CBLModel class]]) {
        // Model-valued property:
        impBlock = ^id(CBLModel* receiver) {
            return [receiver getModelProperty: property];
        };
    } else {
        // Other property type -- use a ValueConverter if we have one:
        ValueConverter converter = valueConverterToClass(propertyClass);
        if (converter) {
            impBlock = ^id(CBLModel* receiver) {
                return [receiver getProperty: property withConverter: converter];
            };
        }
    }

    return impBlock ? imp_implementationWithBlock(impBlock) : NULL;
}


// Generates a method for a property setter.
+ (IMP) impForSetterOfProperty: (NSString*)property ofClass: (Class)propertyClass {
    void (^impBlock)(CBLModel*,id) = nil;

    if ([propertyClass isSubclassOfClass: [CBLModel class]]) {
        // Model-valued property:
        impBlock = ^(CBLModel* receiver, CBLModel* value) {
            [receiver setModel: value forProperty: property];
        };
    } else if ([propertyClass isSubclassOfClass: [NSArray class]]) {
        Class itemClass = [self itemClassForArrayProperty: property];
        if (itemClass == nil) {
            // Untyped array:
            return [super impForSetterOfProperty: property ofClass: propertyClass];
        } else if ([itemClass isSubclassOfClass: [CBLModel class]]) {
            // Model-valued array (to-many relation):
            impBlock = ^(CBLModel* receiver, NSArray* value) {
                [receiver setArray: value forProperty: property ofModelClass: itemClass];
            };
        } else {
            // Scalar-valued array:
            impBlock = ^(CBLModel* receiver, NSArray* value) {
                [receiver setValue: value ofProperty: property];
            };
        }
    } else {
        return [super impForSetterOfProperty: property ofClass: propertyClass];
    }

    return impBlock ? imp_implementationWithBlock(impBlock) : NULL;
}


@end
