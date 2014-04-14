//
//  CBLNestedModel.h
//  CBLNestedModelExample
//
//  Created by Ragu Vijaykumar on 4/11/14.
//  Copyright (c) 2014 RVijay007. All rights reserved.
//

#import <CouchbaseLite/CouchbaseLite.h>

@interface CBLNestedModel : NSObject

- (id)initFromJSON:(id)jsonObject;
- (id)encodeToJSON;

- (void)reparent:(CBLNestedModel*)parent;

@end

@interface CBLNestedModel (CBLModel)

- (void)setOnMutate:(CBLOnMutateBlock)onMutate;

@end

@interface CBLNestedModel (NSObject)

- (NSDictionary*)allProperties;     // PropertyName --> [Attributes]

/**
 * Converts a property attribute to the class it refers to
 * Primitives map to NSNumber
 */
+ (Class)classForPropertyTypeAttribute:(NSString*)propertyTypeAttribute;

@end

