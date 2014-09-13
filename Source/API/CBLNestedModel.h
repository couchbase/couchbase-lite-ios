//
//  CBLNestedModel.h
//  CBLNestedModelExample
//
//  Created by Ragu Vijaykumar on 4/11/14.
//  Copyright (c) 2014 RVijay007. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLJSON.h"

@interface CBLNestedModel : NSObject

/**
 * Override this as the designated initializer and set instance variables to their initial values
 */
- (id)init;

/**
 * If this object is going to be stored in a property, or in an NSArray/NSDictionary which is a property, of a CBLNestedModel,
 * then you must call setParent with the CBLNestedModel parent. You do not have to do anything if it will be stored in a CBLModel
 */
- (void)setParent:(CBLNestedModel*)parent;

/**
 * Anytime you change a property's value for a CBLNestedModel, you must call modified so that the parent CBLModel
 * knows that this is dirty and has information that needs to be saved
 */
- (void)modified;

/**
 * Call this from your setters for properties to make sure that the modification object is passed to child objects
 * if they are instances of CBLNestedModels
 */
- (void)propagateParentTo:(id)object;

@end

//////////////////////////////////////////////////////////////////////////////////////////////////

@interface CBLNestedModel (CBLModel)
// Used by CBL Model to create CBLNestedModels from database
- (id)initFromJSON:(id)jsonObject;
- (id)encodeToJSON;

- (void)setOnMutate:(CBLOnMutateBlock)onMutate;

- (id)convertValueFromJSON:(id)jsonObject toDesiredClass:(Class)desiredPropertyClass representedByPropertyName:(NSString*)propertyName;
+ (id)convertValueToJSON:(id)value;

- (id)copyWithZone:(NSZone*)zone;

@end

//////////////////////////////////////////////////////////////////////////////////////////////////

@interface CBLNestedModel (NSObject)

- (NSDictionary*)allProperties;     // PropertyName --> [Attributes], recursive to all superclasses until CBLNestedModel

/**
 * Converts a property attribute to the class it refers to
 * Primitives map to NSNumber
 */
+ (Class)classForPropertyTypeAttribute:(NSString*)propertyTypeAttribute;

@end

