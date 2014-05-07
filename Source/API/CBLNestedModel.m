//
//  CBLNestedModel.m
//  CBLNestedModelExample
//
//  Created by Ragu Vijaykumar on 4/11/14.
//  Copyright (c) 2014 RVijay007. All rights reserved.
//

#import "CBLNestedModel.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "CBLDatabase.h"
#import "CBLManager.h"
#import "CBLModel.h"
#import "CBLModelFactory.h"

@interface CBLNestedModel ()
@property (copy, nonatomic) CBLOnMutateBlock onMutateBlock;
@property (strong, nonatomic) NSMutableDictionary* documentObject;

@end

@implementation CBLNestedModel
@synthesize onMutateBlock;
@synthesize documentObject;

- (id)init {
    self = [super init];
    if(self) {
        self.documentObject = [NSMutableDictionary mutableCopy];
        self.onMutateBlock = nil;
    }
    
    return self;
}

- (void)setParent:(CBLNestedModel*)parent {
    if(!parent) {
        NSLog(@"Warning: CBLNestedModel parent should never be nil");
    } else {
        self.onMutateBlock = parent.onMutateBlock;
        
        // Get a list of existing properties and keep propagating the onMutateBlock
        NSDictionary* properties = [self allProperties];
        [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [self propagateParentTo:[self valueForKey:key]];
        }];
    }
}

- (void)modified {
    if(self.onMutateBlock)
        self.onMutateBlock();
}


- (void)propagateParentTo:(id)object {
    if(!object)
        return;
    
    if([object isKindOfClass:[NSArray class]]) {
        NSArray* array = (NSArray*)object;
        [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [self propagateParentTo:obj];
        }];
    } else if([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary* dictionary = (NSDictionary*)object;
        [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [self propagateParentTo:obj];
        }];
    } else if([object isKindOfClass:[CBLNestedModel class]]) {
        [object setParent:self];
    }
}

@end

/////////////////////////////////////////////////////////////////////////////////////////////////

@implementation CBLNestedModel (CBLModel)

#pragma mark - Decoding Methods (JSON --> class)

- (id)initFromJSON:(id)jsonObject {
    self = [self init];        // Default initilization
    if(self) {
        if([jsonObject isKindOfClass:[NSDictionary class]]) {
            // It must be a dictionary to represent a class
            // Store it so that we don't lose information in the document that this class might not yet handle.
            NSMutableDictionary* mutableJSONObject = [jsonObject mutableCopy];
            
            // Enumerate through all the properties that this subclass has.
            NSDictionary* properties = [self allProperties];
            [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                NSString* propertyName = key;
                NSArray* propertyAttr = obj;
                Class desiredPropertyClass = [CBLNestedModel classForPropertyTypeAttribute:propertyAttr[0]];
                
                id value = [self convertValueFromJSON:jsonObject[key] toDesiredClass:desiredPropertyClass representedByPropertyName:key];
                if(value) {
                    [self setValue:value forKey:propertyName];
                }
                
                mutableJSONObject[key] = nil;
            }];
            self.documentObject = mutableJSONObject;
        }
    }
    
    return self;
}

- (id)convertValueFromJSON:(id)jsonObject toDesiredClass:(Class)desiredPropertyClass representedByPropertyName:(NSString*)propertyName {
    if(!jsonObject)
        return nil;
    
    id value = nil;
    
    // Block used by collection JSON objects to determine what class to convert values to
    Class(^CollectionClassTypeBlock)(Class klass, NSString* propertyName) = ^Class(Class objClass, NSString* propertyName) {        
        Class klass = [[self class] itemClassForArrayProperty:propertyName];
        if(!klass)
            klass = objClass;

        return klass;
    };
    
    if(desiredPropertyClass == [NSNumber class] ||
       desiredPropertyClass == [NSNull class] ||
       [desiredPropertyClass isSubclassOfClass:[NSString class]]) {
        // JSON compatible objects will be mapped directly to the class variables
        value = jsonObject;
    } else if(desiredPropertyClass == [NSDate class]) {
        value = [CBLJSON dateWithJSONObject:jsonObject];
    } else if(desiredPropertyClass == [NSData class]) {
        value = [CBLJSON dataWithBase64String:jsonObject];
    } else if(desiredPropertyClass == [NSDecimalNumber class]) {
        value = [NSDecimalNumber decimalNumberWithString:jsonObject];
    } else if([desiredPropertyClass isSubclassOfClass:[CBLModel class]]) {
        // We have a relationship where jsonObject is the documentId String
        
        // Search all databases to find the relevant document
        NSArray* databaseNames = [[CBLManager sharedInstance] allDatabaseNames];
        __block CBLDocument* document = nil;
        [databaseNames enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            CBLDatabase* database = [[CBLManager sharedInstance] existingDatabaseNamed:obj error:nil];
            document = [database existingDocumentWithID:jsonObject];
            if(document)
                *stop = YES;
        }];
        
        if(document) {
            // We have a document, but it may be a specific subclass. Attempt to create the subclass.
            value = [[CBLModelFactory sharedInstance] modelForDocument:document];
            if(!value) {
                // The document's type property was not registered, so we need to instantiate directly from the desired property class
                value = [desiredPropertyClass modelForDocument:document];
            }
        }
    } else if([desiredPropertyClass isSubclassOfClass:[CBLNestedModel class]]) {
        // Recursively instantiate the desired property class with the jsonObject
        // Does not handle polymorphism
        // Propagate the modification Object so that changes to nested models can go to top level CBLModel
        
        value = [[desiredPropertyClass alloc] initFromJSON:jsonObject];
    } else if(desiredPropertyClass == [NSArray class]) {
        NSArray* jsonArray = jsonObject;
        
        NSMutableArray* objectArray = [NSMutableArray arrayWithCapacity:[jsonArray count]];
        [jsonArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            id collectionValue = [self convertValueFromJSON:obj toDesiredClass:CollectionClassTypeBlock([obj class], propertyName) representedByPropertyName:propertyName];
            
            if(collectionValue) {
                [objectArray addObject:collectionValue];
            }
        }];
        
        value = objectArray;
    } else if(desiredPropertyClass == [NSDictionary class]) {
        NSDictionary* jsonDictionary = jsonObject;
        
        NSMutableDictionary* objectDict = [NSMutableDictionary dictionaryWithCapacity:[jsonDictionary count]];
        [jsonDictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            id collectionValue = [self convertValueFromJSON:obj toDesiredClass:CollectionClassTypeBlock([obj class], propertyName) representedByPropertyName:propertyName];
            if(collectionValue) {
                objectDict[key] = collectionValue;
            }
        }];
        
        value = objectDict;
    } else {
        NSLog(@"Warning: Unknown type of value to decode in JSON. Desired property class %@.", desiredPropertyClass);
    }
    
    return value;
}

#pragma mark - Encoding Methods (class --> JSON)

- (id)encodeToJSON {
    // Use old documentObject in case it contains more information than our model specifies
    // and replace only with new information
    NSMutableDictionary* classJSON = self.documentObject;
    
    // Get a list of existing properties
    NSDictionary* properties = [self allProperties];
    [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        id value = [CBLNestedModel convertValueToJSON:[self valueForKey:key]];
        if(value) {
            // Do not store nil values
            classJSON[key] = value;
        }
    }];
    
    return classJSON;
}

+ (id)convertValueToJSON:(id)value {
    if(!value)
        return nil;
    
    if([value isKindOfClass:[NSData class]]) {
        value = [CBLJSON base64StringWithData:value];
    } else if ([value isKindOfClass:[NSDate class]]) {
        value = [CBLJSON JSONObjectWithDate: value];
    } else if ([value isKindOfClass:[NSDecimalNumber class]]) {
        value = [value stringValue];
    } else if([value isKindOfClass:[NSString class]] ||
              [value isKindOfClass:[NSNull class]] ||
              [value isKindOfClass:[NSNumber class]]) {
        // JSON-compatible, non-collection objects
        // Must come after NSDecimalNumber since NSDecimalNumber inherits from NSNumber
        return value;
    } else if([value isKindOfClass:[CBLModel class]]) {
        value = [[value document] documentID];
    } else if([value isKindOfClass:[CBLNestedModel class]]) {
        value = [value encodeToJSON];
    } else if([value isKindOfClass:[NSArray class]]) {
        NSArray* array = (NSArray*) value;
        NSMutableArray* returnArray = [@[] mutableCopy];
        [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [returnArray addObject:[CBLNestedModel convertValueToJSON:obj]];
        }];
        value = [returnArray copy];
    } else if([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary* dictionary = (NSDictionary*)value;
        NSMutableDictionary* returnDict = [NSMutableDictionary dictionary];
        [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            // Key should be an NSString
            returnDict[key] = [CBLNestedModel convertValueToJSON:obj];
        }];
        value = [returnDict copy];
        
    } else {
        // Unknown type - log it
        NSLog(@"Warning: Unknown type of value to encode. Value class name is %@.", [value class]);
        value = nil;
    }
    
    return value;
}

- (void)setOnMutate:(CBLOnMutateBlock)onMutate {
    self.onMutateBlock = onMutate;
    
    // Get a list of existing properties and propagate the onMutateBlock to classes that need it
    NSDictionary* properties = [self allProperties];
    [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self propagateParentTo:[self valueForKey:key]];
    }];
}

+ (Class) itemClassForArrayProperty: (NSString*)property {
    SEL sel = NSSelectorFromString([property stringByAppendingString: @"ItemClass"]);
    if ([self respondsToSelector: sel]) {
        return (Class)objc_msgSend(self, sel);
    }
    return Nil;
}

@end

//////////////////////////////////////////////////////////////////////////////////////////////////

@implementation CBLNestedModel (NSObject)

- (NSDictionary*)allProperties {
    static NSMutableDictionary* propertyDictionary = nil;
    
    // Property lists don't change during runtime, so store computed properties for fast O(1) access
    // on subsequent calls
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        propertyDictionary = [NSMutableDictionary dictionary];
    });
    
    Class klass = [self class];
    NSString* klassString = NSStringFromClass(klass);
    NSMutableDictionary* dictionary = propertyDictionary[klassString];
    
    if(!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
        
        // Get all properties we have until we hit CBLNestedModel
        // Allows us to have multiple subclasses of CBLNestedModel, but does not support polymorphism.
        while(klass != [CBLNestedModel class]) {
            unsigned count;
            objc_property_t* properties = class_copyPropertyList(klass, &count);
            for (unsigned i = 0; i < count; i++) {
                objc_property_t property = properties[i];
                
                const char* propertyNameC = property_getName(property);
                NSString* propertyName = [NSString stringWithUTF8String:propertyNameC];
                const char* propertyAttrC = property_getAttributes(property);
                NSString* propertyAttrS = [NSString stringWithUTF8String:propertyAttrC];
                NSArray* propertyAttr = [propertyAttrS componentsSeparatedByString:@","];
                
                dictionary[propertyName] = propertyAttr;
            }
            free(properties);
            klass = [klass superclass];
        }
        
        propertyDictionary[klassString] = dictionary;
    }

    return dictionary;
}

+ (Class)classForPropertyTypeAttribute:(NSString*)propertyTypeAttribute {
    Class typeClass = nil;
    
    if([propertyTypeAttribute hasPrefix:@"T@"] && [propertyTypeAttribute length] > 2) {
        NSString* typeClassName = [propertyTypeAttribute substringWithRange:NSMakeRange(3, [propertyTypeAttribute length]-4)];
        typeClass = NSClassFromString(typeClassName);
        if(!typeClass) {
            NSLog(@"Warning: PropertyTypeAttrbute did not match to a valid class: %@-->%@", propertyTypeAttribute, typeClassName);
        }
    } else if(![propertyTypeAttribute hasPrefix:@"T@"] && [propertyTypeAttribute length] == 2) {
        // This is a primitive object
        typeClass = [NSNumber class];
    }
    
    return typeClass;
}

@end


