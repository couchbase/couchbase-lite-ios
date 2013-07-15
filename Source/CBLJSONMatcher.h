//
//  CBLJSONMatcher.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/10/13.
//
//

#import <Cocoa/Cocoa.h>
@class CBLJSONMatcher, CBLJSONArrayMatcher, CBLJSONParser;


typedef void (^CBLJSONStartBlock)(CBLJSONParser*);

typedef bool (^CBLJSONMatchBlock)(id, CBLJSONParser*);
typedef bool (^CBLJSONMatchNullBlock)(CBLJSONParser*);
typedef bool (^CBLJSONMatchBoolBlock)(bool, CBLJSONParser*);
typedef bool (^CBLJSONMatchIntBlock)(SInt64, CBLJSONParser*);
typedef bool (^CBLJSONMatchDoubleBlock)(double, CBLJSONParser*);
typedef bool (^CBLJSONMatchStringBlock)(NSString*, CBLJSONParser*);
typedef bool (^CBLJSONMatchCStringBlock)(const UInt8*,size_t, CBLJSONParser*);


/** A template object that matches a JSON value being parsed and can act on the value. */
@interface CBLJSONMatcher : NSObject
+ (instancetype) boolMatcher: (CBLJSONMatchBoolBlock)onMatched;
+ (instancetype) intMatcher: (CBLJSONMatchIntBlock)onMatched;
+ (instancetype) doubleMatcher: (CBLJSONMatchDoubleBlock)onMatched;
+ (instancetype) stringMatcher: (CBLJSONMatchStringBlock)onMatched;

@property (copy) CBLJSONMatchBlock onMatch;
@property (copy) CBLJSONMatchBoolBlock onMatchBool;
@property (copy) CBLJSONMatchIntBlock onMatchInt;
@property (copy) CBLJSONMatchDoubleBlock onMatchDouble;
@property (copy) CBLJSONMatchStringBlock onMatchString;
@property (copy) CBLJSONMatchCStringBlock onMatchCString;
@property (copy) CBLJSONMatchNullBlock onMatchNull;

@end


/** A JSON matcher for arrays. */
@interface CBLJSONArrayMatcher : CBLJSONMatcher
@property (copy) CBLJSONStartBlock onStart;
@property (readwrite) CBLJSONMatcher* itemMatcher;
@end


/** A JSON matcher for objects (aka dictionaries, aka maps). */
@interface CBLJSONObjectMatcher : CBLJSONMatcher
@property NSMutableDictionary* itemMatchers;
@property CBLJSONMatcher* defaultItemMatcher;
@end


/** A streaming JSON parser that feeds the output through a hierarchy of matchers. */
@interface CBLJSONParser : NSObject
- (instancetype) initWithMatcher: (CBLJSONMatcher*)rootMatcher;
- (BOOL) parseBytes: (const void*)bytes length: (size_t)length;
- (BOOL) parseData: (NSData*)data;
- (BOOL) finish;
@property (readonly) NSString* errorString;

@property (readonly) CBLJSONMatcher* currentMatcher;
@property (readonly) CBLJSONMatcher* parentMatcher;
@end



/*
@interface CBLJSONMatcher (Protected)
- (bool) matchInt: (SInt64)value withParser: (CBLJSONParser*)parser;
- (bool) matchDouble: (double)value withParser: (CBLJSONParser*)parser;
- (bool) matchString: (NSString*)value withParser: (CBLJSONParser*)parser;
- (bool) matchCString: (const UInt8*)chars length: (size_t)length withParser: (CBLJSONParser*)parser;

- (bool) startArray;
@property (readonly) CBLJSONMatcher* itemMatcher;
- (bool) startObject;
- (bool) end;
@end


@interface CBLJSONArrayMatcher (Protected)
- (bool) matchItem: (id)item;
@end


@interface CBLJSONObjectMatcher (Protected)
- (CBLJSONMatcher*) matcherForKey: (const UInt8*)chars length: (size_t)length;
@end
*/