//
//  CBLDynamicObject.h
//  MYUtilities
//
//  Created by Jens Alfke on 8/6/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


/** A generic class with runtime support for dynamic properties.
    You can subclass this and declare properties in the subclass without needing to implement them or make instance variables; simply note them as '@@dynamic' in the @@implementation.
    The dynamic accessors will be bridged to calls to -getValueOfProperty: and setValue:ofProperty:, allowing you to easily store property values in an NSDictionary or other container. */
@interface CBLDynamicObject : NSObject

/** Returns the names of all properties defined in this class and superclasses up to CBLDynamicObject. */
+ (NSSet*) propertyNames;

/** Returns the value of a named property.
    This method will only be called for properties that have been declared in the class's @@interface using @@property.
    You must override this method -- the base implementation just raises an exception. */
- (id) getValueOfProperty: (NSString*)property;

/** Sets the value of a named property.
    This method will only be called for properties that have been declared in the class's @@interface using @@property, and are not declared readonly.
    You must override this method -- the base implementation just raises an exception.
    @return YES if the property was set, NO if it isn't settable; an exception will be raised.
    Default implementation returns NO. */
- (BOOL) setValue: (id)value ofProperty: (NSString*)property;


// FOR SUBCLASSES TO CALL:

/** Given the name of an object-valued property, returns the class of the property's value.
    Returns nil if the property doesn't exist, or if its type isn't an object pointer or is 'id'. */
+ (Class) classOfProperty: (NSString*)propertyName;

+ (NSString*) getterKey: (SEL)sel;
+ (NSString*) setterKey: (SEL)sel;

// ADVANCED STUFF FOR SUBCLASSES TO OVERRIDE:

+ (IMP) impForGetterOfProperty: (NSString*)property ofClass: (Class)propertyClass;
+ (IMP) impForSetterOfProperty: (NSString*)property ofClass: (Class)propertyClass;
+ (IMP) impForGetterOfProperty: (NSString*)property ofProtocol: (Protocol*)propertyProtocol;
+ (IMP) impForSetterOfProperty: (NSString*)property ofProtocol: (Protocol*)propertyProtocol;
+ (IMP) impForGetterOfProperty: (NSString*)property ofType: (const char*)propertyType;
+ (IMP) impForSetterOfProperty: (NSString*)property ofType: (const char*)propertyType;

@end

/** Given an Objective-C class object, a property name, and a BOOL for whether the property should be readwrite,
    return YES if a property with the name exists , NO otherwise.
    If setter argument is YES but property is declared readonly, also returns NO.
    Information about the property is returned by reference: the subclass of cls that declares the property, 
    and the property string part of the property attributes string.
 */
BOOL CBLGetPropertyInfo(Class cls,
                       NSString *propertyName,
                       BOOL setter,
                       Class *declaredInClass,
                       const char* *propertyType);


/** Given an Objective-C property type string, returns the property type as a Class object, 
    or nil if a class does not apply or no such property is present.
    See Property Type String section of the Objective-C Runtime Programming Guide 
    for more information about the format of the string. */
Class CBLClassFromType(const char* propertyType, Class relativeToClass);

/** Same as MYClassFromType, except for protocols. */
Protocol* CBLProtocolFromType(const char* propertyType, Class relativeToClass);
