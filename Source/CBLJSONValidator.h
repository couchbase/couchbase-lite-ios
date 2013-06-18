//
//  CBLJSONValidator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/13/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Validates JSON objects against JSON-Schema specs. Follows draft 4 of the standard:
    http://json-schema.org/documentation.html
    This class is thread-safe. */
@interface CBLJSONValidator : NSObject

/** Convenience method that loads a schema from a URL (file or HTTP), creates a validator on it, and validates the given object.
    The validator instance is cached, so subsequent calls with the same URL will be fast. */
+ (bool) validateJSONObject: (id)object
            withSchemaAtURL: (NSURL*)schemaURL
                      error: (NSError**)error;


/** Convenience method that loads a schema from a URL (file or HTTP), creates a validator on it, and validates the given object.
    The validator instance is cached, so subsequent calls with the same URL will be fast. */
+ (bool) validateJSONObject: (id)object
            withSchemaNamed: (NSString*)resourceName
                      error: (NSError**)error;

/** Loads a schema from a URL (file or HTTP) and creates a validator on it.
    The validator instance is cached, so subsequent calls with the same URL will be fast. */
+ (CBLJSONValidator*) validatorForSchemaAtURL: (NSURL*)schemaURL
                                        error: (NSError**)error;


/** Initializes a new CBLJSONSchema object from a schema dictionary. */
- (id) initWithSchema: (NSDictionary*)schema;


@property (readonly) NSDictionary* schema;

/** Setting this to true blocks loading remote schema via "$ref" properties. An error will be returned instead. */
@property bool offline;

/** Checks whether this is a valid JSON-Schema, by fetching the official JSON-Schema schema (over HTTP) and validating the dictionary with it. */
- (bool) selfValidate: (NSError**)outError;

/** Validates a JSON object against this schema. */
- (bool) validateJSONObject: (id)object
                      error: (NSError**)error;


/** Forces a schema dictionary into the cache for a given URL. Subsequent schema lookups for that URL will immediately return this instance instead of accessing the network or filesystem. Unlike regular cached schema, these never expire. */
+ (void) registerSchema: (NSDictionary*)schema forURL: (NSURL*)schemaURL;

@end


/** NSError domain for JSON-Schema validation errors.
    The "path" property of the userInfo will be a JSON-pointer string locating the item with the error. */
extern NSString* const CBJLSONValidatorErrorDomain;
