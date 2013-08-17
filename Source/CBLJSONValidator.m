//
//  CBLJSONValidator.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/13/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Inspired by https://github.com/akempgen/ALEXJSONValidation
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#import "CBLJSONValidator.h"
#import "CBLJSON.h"


#define kJSONSchemaSchemaURLStr @"http://json-schema.org/draft-04/schema"


NSString* const CBJLSONValidatorErrorDomain = @"CBLJSONValidator";


@implementation CBLJSONValidator
{
    NSDictionary* _rootSchema;
    bool _offline;
}


@synthesize schema=_rootSchema, offline=_offline;


- (id)initWithSchema: (NSDictionary*)schema {
    NSParameterAssert(schema != nil);
    self = [super init];
    if (self) {
        _rootSchema = schema;
    }
    return self;
}


- (bool) selfValidate: (NSError**)outError {
    return [[self class] validateJSONObject: _rootSchema
                            withSchemaAtURL: [NSURL URLWithString: kJSONSchemaSchemaURLStr]
                                      error: outError];
}


#pragma mark - VALIDATION:


// Convenience function for setting an error
static bool FAIL(NSError** outError, NSString* message, ...) {
    if (outError) {
        va_list args;
        va_start(args, message);
        message = [[NSString alloc] initWithFormat: message arguments: args];
        va_end(args);
        // userInfo.path starts out as "/", but it's a mutable string, and subsequence calls to
        // PROPAGATE() on the way up the call chain will prepend path components to it.
        NSDictionary* info = @{NSLocalizedDescriptionKey: message,
                               @"path": [NSMutableString stringWithString: @"/"]};
        *outError = [NSError errorWithDomain: CBJLSONValidatorErrorDomain code: 1 userInfo: info];
    }
    return false;
}


// Propagates an error from a nested object, adding to the "path" property in the NSError object.
static bool PROPAGATE(NSError** outError, id pathItem) {
    if (outError) {
        NSMutableString* path = (*outError).userInfo[@"path"];
        if (path.length > 1)
            [path insertString: @"/" atIndex: 1];
        [path insertString: [pathItem description] atIndex: 1];
    }
    return false;
}


+ (bool) validateJSONObject: (id)object withSchemaAtURL: (NSURL*)schemaURL error: (NSError**)error {
	CBLJSONValidator* validator = [self validatorForSchemaAtURL: schemaURL error: error];
	return [validator validateJSONObject: object error: error];
}


+ (bool) validateJSONObject: (id)object
            withSchemaNamed: (NSString*)resourceName
                      error: (NSError**)error
{
    NSURL* url = [[NSBundle mainBundle] URLForResource: resourceName withExtension: @"json"];
    NSAssert(url != nil, @"No such JSON schema resource '%@.json'", resourceName);
    return [self validateJSONObject: object withSchemaAtURL: url error: error];
}


- (bool) validateJSONObject: (id)object error: (NSError**)error {
	return [self validateJSONObject: object withSchema: _rootSchema error: error];
}


static bool validateForAll(id objOrArray, bool (^block)(id)) {
    if ([objOrArray isKindOfClass: [NSArray class]]) {
        for (id obj in objOrArray) {
            if (!block(obj))
                return false;
        }
    } else if (objOrArray != nil) {
        return block(objOrArray);
    }
    return true;
}


// Follow a reference to another location in the schema, or into a different schema entirely
- (bool) validateJSONObject: (id)object
               forReference: (NSString*)ref
                      error: (NSError**)outError
{
    NSString *schemaURI, *pointer;
    NSRange hashRange = [ref rangeOfString: @"#"];
    if (hashRange.location == NSNotFound) {
        schemaURI = ref;
        pointer = nil;
    } else {
        schemaURI = [ref substringToIndex: hashRange.location];
        pointer = [ref substringFromIndex: NSMaxRange(hashRange)];
    }

    CBLJSONValidator* validator = self;
    if (schemaURI.length > 0) {
        // Remote ref: load validator from URL:
        NSURL* url = [NSURL URLWithString: schemaURI];
        if (!url)
            return FAIL(outError, @"Schema error: Invalid URL in $ref to <%@>", schemaURI);
        validator = [[self class] validatorForSchemaAtURL: url offline: _offline error: outError];
        if (!validator)
            return false;
    }

    NSDictionary* refSchema = validator.schema;
    if (pointer.length) {
        // Follow JSON-Pointer portion of ref:
        refSchema = [CBLJSON valueAtPointer: pointer inObject: refSchema];
        if (![refSchema isKindOfClass: [NSDictionary class]])
            return FAIL(outError, @"Schema error: Invalid JSON pointer '%@'", pointer);
    }
    
    return [validator validateJSONObject: object withSchema: refSchema error: outError];
}


- (bool) validateJSONObject: (id)object
                 withSchema: (NSDictionary*)schema
                      error: (NSError**)outError
{
	if (![schema isKindOfClass: [NSDictionary class]])
        return FAIL(outError, @"Schema error: expected an object");

    // $ref: Resolve a JSON Reference:
	NSString *ref = schema[@"$ref"];
	if (ref)
        return [self validateJSONObject: object forReference: ref error: outError];

	// If we got a nil value, something's missing:
	if (!object) {
		return FAIL(outError, @"Missing required value");
	}

    // allOf
    NSArray* allOf = schema[@"allOf"];
    if (allOf && !validateForAll(allOf, ^bool(NSDictionary* schema) {
                return [self validateJSONObject: object withSchema: schema error: outError];
            })) {
        return false;
    }

    // anyOf
    NSArray* anyOf = schema[@"anyOf"];
    if (anyOf) {
        bool foundOne = false;
        for (NSDictionary* option in anyOf) {
            if ([self validateJSONObject: object withSchema: option error: outError]) {
                foundOne = true;
                break;
            }
        }
        if (!foundOne)
            return FAIL(outError, @"value is not of any allowed schema");
    }

    // oneOf
    NSArray* oneOf = schema[@"oneOf"];
    if (oneOf) {
        bool foundOne = false;
        for (NSDictionary* option in oneOf) {
            if ([self validateJSONObject: object withSchema: option error: outError]) {
                if (foundOne)
                    return FAIL(outError, @"Value matches mutually exclusive options");
                foundOne = true;
            }
        }
        if (!foundOne)
            return FAIL(outError, @"value is not of any allowed schema");
    }

    // not
    NSDictionary* not = schema[@"not"];
    if (not) {
        if ([self validateJSONObject: object withSchema: not error: nil])
            return FAIL(outError, @"value matched a schema it shouldn't have"); //FIX: Better message
    }

	// type
    id type = schema[@"type"];
    if (type) {
        bool valid = false;
        if ([type isKindOfClass: [NSArray class]]) {
            for (id allowedType in type) {
                valid = [self isValue: object ofType: allowedType];
                if (valid)
                    break;
            }
            if (!valid && outError)
                type = [type componentsJoinedByString: @", "];
        } else {
            valid = [self isValue: object ofType: type];
        }
        if (!valid) {
            NSString* desc = nil;
            if (outError) // don't bother generating JSON if it's not going into an NSError
                desc = [CBLJSON stringWithJSONObject: object
                                             options: CBLJSONWritingAllowFragments error: nil];
            return FAIL(outError, @"expected %@; got %@", type, desc);
        }
    }

	// enum
    NSArray *enumArray = schema[@"enum"];
    if (enumArray && ![enumArray containsObject: object])
        return FAIL(outError, @"value is not of allowed enumerated set");

    // Now type-specific tests:
    
	if ([object isKindOfClass: [NSDictionary class]]) {
        // minProperties
        NSUInteger count = [object count];
        NSNumber* minProperties = schema[@"minProperties"];
        if (minProperties) {
            if (count < minProperties.unsignedIntegerValue)
                return FAIL(outError, @"Object must have at least %@ properties",
                            minProperties);
        }

        // maxProperties
        NSNumber* maxProperties = schema[@"maxProperties"];
        if (maxProperties) {
            if (count > maxProperties.unsignedIntegerValue)
                return FAIL(outError, @"Object must have no more than %@ properties",
                            maxProperties);
        }

        // required
        for (NSString* property in schema[@"required"]) {
            if (!object[property])
                return FAIL(outError, @"Missing required property '%@'", property);
        }

        // properties
        NSMutableSet *validatedPropertyKeys = nil;
        NSDictionary* properties = schema[@"properties"];
        if (properties) {
            validatedPropertyKeys = [NSMutableSet setWithArray: [properties allKeys]];
            for (NSString *property in properties) {
                id value = object[property];
                if (value && ![self validateJSONObject: value
                                            withSchema: properties[property]
                                                 error: outError])
                    return PROPAGATE(outError, property);
            }
        }

        // patternProperties
        NSDictionary* patternProperties = schema[@"patternProperties"];
        for (NSString *propertyPattern in patternProperties) {
            NSError* regexError;
            NSRegularExpression *propertyRegEx;
            propertyRegEx = [NSRegularExpression regularExpressionWithPattern: propertyPattern
                                                                      options: 0
                                                                        error: &regexError];
            if (!propertyRegEx) {
                return FAIL(outError, @"Bad JSON schema: Couldn't parse regex: /%@/ [error: %@]",
                                propertyPattern, regexError);
            }
            for (NSString *objectProperty in object) {
                NSRange range = NSMakeRange(0, [objectProperty length]);
                NSTextCheckingResult *result = [propertyRegEx firstMatchInString: objectProperty
                                                                         options: 0 range: range];
                if (result) {
                    // build validatedPropertyKeys set for additionalProperties check
                    if (!validatedPropertyKeys)
                        validatedPropertyKeys = [NSMutableSet setWithObject: objectProperty];
                    else
                        [validatedPropertyKeys addObject: objectProperty];
                    if (![self validateJSONObject: object[objectProperty]
                                       withSchema: patternProperties[propertyPattern]
                                            error: outError])
                        return PROPAGATE(outError, objectProperty);
                }
            }
        }

        // additionalProperties
        id additionalProperties = schema[@"additionalProperties"];
        if ([additionalProperties isKindOfClass: [NSNumber class]]) {
            if ([additionalProperties boolValue] == false) {
                if (![[NSSet setWithArray: [object allKeys]] isSubsetOfSet: validatedPropertyKeys])
                    return FAIL(outError, @"illegal extra properties");
            }
        } else if ([additionalProperties isKindOfClass: [NSDictionary class]]) {
            for (NSString *property in object) {
                if (![validatedPropertyKeys containsObject: property]) {
                    if (![self validateJSONObject: object[property]
                                       withSchema: additionalProperties
                                            error: outError])
                        return PROPAGATE(outError, property);
                }
            }
        }

        // dependencies
        id dependencies = schema[@"dependencies"];
        for (NSString *dependendingProperty in dependencies) {
            if (object[dependendingProperty]) {
                id dependency = dependencies[dependendingProperty];
                if ([dependency isKindOfClass: [NSArray class]]) {
                    for (NSString *dependencySubkey in dependency) {
                        if (object[dependencySubkey] == nil)
                            return FAIL(outError, @"missing dependent property '%@'",
                                        dependencySubkey);
                    }
                } else if (dependency) {
                    if (![self validateJSONObject: object
                                       withSchema: dependency
                                            error: outError])
                        return false;
                }
            }
        }
        
    } else if ([object isKindOfClass: [NSNumber class]]) {
        // 5.1. Validation keywords for numeric instances (number and integer)
        double objectValue = [object doubleValue];
		// maximum
        NSNumber *maximum = schema[@"maximum"];
        if (maximum) {
            bool exclusiveMaximum = [schema[@"exclusiveMaximum"] boolValue];
            bool valid;
            if (exclusiveMaximum)
                valid = (objectValue < maximum.doubleValue);
            else
                valid = (objectValue <= maximum.doubleValue);
            if (!valid)
                return FAIL(outError, @"numeric value above maximum");
		}
		// minimum
        NSNumber *minimum = schema[@"minimum"];
        if (minimum) {
            bool exclusiveMinimum = [schema[@"exclusiveMinimum"] boolValue];
            bool valid;
            if (exclusiveMinimum)
                valid = (objectValue > minimum.doubleValue);
            else
                valid = (objectValue >= minimum.doubleValue);
            if (!valid)
                return FAIL(outError, @"numeric value below minimum");
        }
        // multipleOf
        NSNumber *multipleOf = schema[@"multipleOf"];
        if (multipleOf) {
            // You'd think fmod would be the right tool for this, but it has more roundoff error
            double result = objectValue / multipleOf.doubleValue;
            if (result != floor(result))
                return FAIL(outError, @"numeric value is not divisible by %@", multipleOf);
        }
        
	} else if ([object isKindOfClass: [NSString class]]) {
        // 5.2. Validation keywords for strings
		// maxLength
        NSNumber *maxLength = schema[@"maxLength"];
        if (maxLength) {
            if ([object length] > [maxLength unsignedIntegerValue])
                return FAIL(outError, @"string is too long");
        }

        // minLength
        NSNumber *minLength = schema[@"minLength"];
        if (minLength) {
            if ([object length] < [minLength unsignedIntegerValue])
                return FAIL(outError, @"string is too short");
        }

        // pattern
        NSString *pattern = schema[@"pattern"];
        if (pattern) {
            NSError *regexError;
            NSRegularExpression *regEx = [NSRegularExpression regularExpressionWithPattern: pattern
                                                                   options: 0 error: &regexError];
            if (!regEx)
                return FAIL(outError, @"Bad JSON schema: Couldn't parse regex: %@ [error: %@]",
                                pattern, regexError);
            if (![regEx firstMatchInString: object
                                   options: 0
                                     range: NSMakeRange(0, [object length])])
                return FAIL(outError, @"string doesn't match pattern");
        }
            
	} else if ([object isKindOfClass: [NSArray class]]) {
        // 5.3. Validation keywords for arrays
		// maxItems
        NSNumber *maxItems = schema[@"maxItems"];
        if (maxItems && [object count] > [maxItems unsignedIntegerValue])
                return FAIL(outError, @"array is too long");

		// minItems
        NSNumber *minItems = schema[@"minItems"];
        if (minItems && [object count] < [minItems unsignedIntegerValue])
            return FAIL(outError, @"array is too short");

        // uniqueItems
        if ([schema[@"uniqueItems"] boolValue]) {
            // FIX: This doesn't consider booleans and 0/1 to be distinct values
            NSSet *set = [NSSet setWithArray: object];
            if ([set count] < [object count])
                return FAIL(outError, @"array items are not unique");
        }

		// items
        id items = schema[@"items"];
        if ([items isKindOfClass: [NSArray class]]) {
            NSUInteger index = 0;
            for (NSDictionary *tupleSchema in items) {
                id item = (index < [object count] ? object[index] : nil);
                if (![self validateJSONObject: item withSchema: tupleSchema error: outError])
                    return PROPAGATE(outError, @(index));
                index++;
            }

            id additionalItems = schema[@"additionalItems"];
            if ([additionalItems isKindOfClass: [NSNumber class]]) {
                if ([additionalItems boolValue] == false) {
                    if ([object count] > [items count])
                        return FAIL(outError, @"array has extra items");
                }
            } else if (additionalItems) {
                for (NSUInteger index = [items count]; index < [object count]; index++) {
                    if (![self validateJSONObject: object[index]
                                       withSchema: additionalItems
                                            error: outError])
                        return PROPAGATE(outError, @(index));
                }
            }

        } else if (items) {
            __block NSUInteger index = 0;
            return validateForAll(object, ^bool(id item) {
                if (![self validateJSONObject: item withSchema: items error: outError])
                    return PROPAGATE(outError, @(index));
                index++;
                return true;
            });
        }
	}

	return true;
}


#pragma mark - TYPE-CHECKING:


static inline bool numberIsBoolean(NSNumber* n) {
    return n.objCType[0] == @encode(BOOL)[0];
}

static inline bool numberIsInteger(NSNumber* n) {
    double value = n.doubleValue;
    return value == floor(value) && !numberIsBoolean(n);
}


- (bool) isValue: (id)object ofType: (NSString*)type {
	if ([type isEqualToString: @"string"]) {
        return [object isKindOfClass: [NSString class]];
    } else if ([type isEqualToString: @"object"]) {
        return [object isKindOfClass: [NSDictionary class]];
    } else if ([type isEqualToString: @"array"]) {
        return [object isKindOfClass: [NSArray class]];
    } else if ([type isEqualToString: @"null"]) {
        return [object isKindOfClass: [NSNull class]];
    } else {
        // Remaining types are all NSNumbers
        if (![object isKindOfClass: [NSNumber class]])
            return false;
        if ([type isEqualToString: @"number"]) {
            return !numberIsBoolean(object);
        } else if ([type isEqualToString: @"integer"]) {
            return numberIsInteger(object);
        } else if ([type isEqualToString: @"boolean"]) {
            return numberIsBoolean(object);
        } else {
            return false;
        }
    }
}


#pragma mark - CACHE / REGISTRY:


static NSMutableDictionary* sRegistry;
static NSCache* sCache;


+ (void) registerSchema: (NSDictionary*)schema forURL: (NSURL*)schemaURL {
    CBLJSONValidator* validator = [[self alloc] initWithSchema: schema];
    @synchronized(self) {
        if (!sRegistry)
            sRegistry = [[NSMutableDictionary alloc] init];
        sRegistry[schemaURL] = validator;
    }
#ifdef LogTo
    LogTo(JSONSchema, @"Registered JSON Schema <%@>", schemaURL);
#endif
}


+ (CBLJSONValidator*) validatorForSchemaAtURL: (NSURL*)schemaURL error: (NSError**)error {
    return [self validatorForSchemaAtURL: schemaURL offline: false error: error];
}


+ (CBLJSONValidator*) validatorForSchemaAtURL: (NSURL*)schemaURL
                                      offline: (bool)offline
                                        error: (NSError**)error
{
	CBLJSONValidator* validator;
    @synchronized(self) {
        validator = [sCache objectForKey: schemaURL];
        if (!validator)
            validator = sRegistry[schemaURL];
    }

	if (!validator) {
#ifdef LogTo
        LogTo(JSONSchema, @"Loading schema from <%@>...", schemaURL);
#endif
		NSDate *startDate = [NSDate date];

        if (offline && ![schemaURL isFileURL]) {
            if (error)
                *error = [NSError errorWithDomain: CBJLSONValidatorErrorDomain code: 3
                                         userInfo: @{NSLocalizedDescriptionKey:
                                                         @"Cannot load remote schema in offline mode"}];
            return nil;
        }

		// Load the schema data from file or over the network
		NSData *data = [NSData dataWithContentsOfURL: schemaURL options: 0 error: error];
        if (!data)
            return nil;

		// Deserialize the schema
		NSDictionary* schema = [NSJSONSerialization JSONObjectWithData: data
                                                               options: 0 error: error];
        if (!schema)
            return nil;
        if (![schema isKindOfClass: [NSDictionary class]]) {
            if (error)
                *error = [NSError errorWithDomain: CBJLSONValidatorErrorDomain code: 2
                                         userInfo: @{NSLocalizedDescriptionKey:
                                                         @"Schema is not a JSON object"}];
            return nil;
        }
        validator = [[self alloc] initWithSchema: schema];

		// Cache for future use
        NSUInteger cost = (NSUInteger)ceil(data.length*-[startDate timeIntervalSinceNow]);
        @synchronized(self) {
            if (!sCache) {
                sCache = [[NSCache alloc] init];
                sCache.name = [self description];
            }
            [sCache setObject: validator forKey: schemaURL cost: cost];
        }
	}
	return validator;
}


@end
