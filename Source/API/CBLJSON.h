//
//  CBLJSON.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLBase.h"

NS_ASSUME_NONNULL_BEGIN

/** Identical to the corresponding NSJSON option flags. */
enum {
    CBLJSONReadingMutableContainers = (1UL << 0),
    CBLJSONReadingMutableLeaves = (1UL << 1),
    CBLJSONReadingAllowFragments = (1UL << 2)
};
typedef NSUInteger CBLJSONReadingOptions;

/** Identical to the corresponding NSJSON option flags, with one addition. */
enum {
    CBLJSONWritingPrettyPrinted = (1UL << 0),
    
    CBLJSONWritingAllowFragments = (1UL << 23)  /**< Allows input to be an NSString or NSValue. */
};
typedef NSUInteger CBLJSONWritingOptions;


/** Useful extensions for JSON serialization/parsing. */
@interface CBLJSON : NSJSONSerialization

/** Same as -dataWithJSONObject... but returns an NSString. */
+ (nullable NSString*) stringWithJSONObject:(id)obj
                                    options:(CBLJSONWritingOptions)opt
                                      error:(NSError**)error;

+ (nullable id) JSONObjectWithData:(NSData *)data;

+ (nullable NSData*) dataWithJSONObject:(id)obj;

/** Given valid JSON data representing a dictionary, inserts the contents of the given NSDictionary into it and returns the resulting JSON data.
    This does not parse or regenerate the JSON, so it's quite fast.
    But it will generate invalid JSON if the input JSON begins or ends with whitespace, or if the dictionary contains any keys that are already in the original JSON. */
+ (NSData*) appendDictionary: (CBLJSONDict*)dict
        toJSONDictionaryData: (NSData*)json;

/** Same as above but inserts a pre-encoded JSON dictionary instead of an NSDictionary. */
+ (NSData*) appendJSONDictionaryData: (NSData*)extraJson
                toJSONDictionaryData: (NSData*)json;

/** Encodes an NSDate as a string in ISO-8601 format. */
+ (NSString*) JSONObjectWithDate: (NSDate*)date;
+ (NSString*) JSONObjectWithDate: (NSDate*)date timeZone:(NSTimeZone *)tz;

/** Parses an ISO-8601 formatted date string to an NSDate object.
    If the object is not a string, or not valid ISO-8601, or nil, it returns nil. */
+ (nullable NSDate*) dateWithJSONObject: (nullable id)jsonObject;

/** Parses an ISO-8601 formatted date string to an absolute time (timeSinceReferenceDate).
    If the object is not a string, or not valid ISO-8601, or nil, it returns a NAN value. */
+ (CFAbsoluteTime) absoluteTimeWithJSONObject: (nullable id)jsonObject;

/** Follows a JSON-Pointer, returning the value pointed to, or nil if nothing.
    See spec at: http://tools.ietf.org/html/draft-ietf-appsawg-json-pointer-04 */
+ (nullable id) valueAtPointer: (NSString*)pointer inObject: (nullable id)object;

/** Encodes an NSData as a string in Base64 format. */
+ (NSString*) base64StringWithData: (NSData*)data;

/** Parses a Base64-encoded string into an NSData object.
    If the object is not a string, or not valid Base64, or nil, it returns nil. */
+ (nullable NSData*) dataWithBase64String: (nullable id)jsonObject;

/** Estimates the amount of memory used by the object and those it references. */
+ (size_t) estimateMemorySize: (id)object;

@end


/** Wrapper for an NSArray of JSON data, that avoids having to parse the data if it's not used.
    NSData objects in the array will be parsed into native objects before being returned to the caller from -objectAtIndex. */
@interface CBLLazyArrayOfJSON : NSArray

/** Initialize a lazy array.
    @param array   An NSArray of NSData objects, each containing JSON. */
- (instancetype) initWithMutableArray: (NSMutableArray*)array;
@end


typedef void (^CBLOnMutateBlock)();

/** Protocol for classes whose instances can encode themselves as JSON.
    Such classes can be used directly as property types in CBLModel subclasses. */
@protocol CBLJSONEncoding <NSObject>
- (nullable instancetype) initWithJSON: (id)jsonObject;
- (id) encodeAsJSON;

@optional
/** If an implementation has mutable persistent state, it should implement this method.
    The implementation should save a copy of the block in an instance variable, and call the block
    whenever the instance's state has changed such that -encodeAsJSON will now return a different
    result.
    This allows the object's owner (typically a CBLModel) to detect such changes and mark itself
    as needing to be saved. */
- (void) setOnMutate: (CBLOnMutateBlock)onMutate;
@end


NS_ASSUME_NONNULL_END
