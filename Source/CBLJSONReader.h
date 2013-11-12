//
//  CBLJSONReader.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/30/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLJSONMatcher, CBLJSONArrayMatcher, CBLJSONDictMatcher;


/** A streaming JSON parser that feeds the output through a hierarchy of matchers. */
@interface CBLJSONReader : NSObject

- (instancetype) initWithMatcher: (CBLJSONMatcher*)rootMatcher;

- (BOOL) parseBytes: (const void*)bytes length: (size_t)length;
- (BOOL) parseData: (NSData*)data;
- (BOOL) finish;

@property (readonly) NSString* errorString;

@end



@interface CBLJSONMatcher : NSObject
- (bool) matchValue: (id)value;
- (CBLJSONArrayMatcher*) startArray;
- (CBLJSONDictMatcher*) startDictionary;
- (id) end;
@end



@interface CBLJSONArrayMatcher : CBLJSONMatcher
@end



@interface CBLJSONDictMatcher : CBLJSONMatcher
@property (readonly) NSString* key;
- (bool) matchValue:(id)value forKey: (NSString*)key;
@end



@interface CBLTemplateMatcher : CBLJSONDictMatcher
- (id)initWithTemplate: (id)template;
@end

