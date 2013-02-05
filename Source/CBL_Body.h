//
//  CBL_Body.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** A request/response/document body, stored as either JSON or an NSDictionary. */
@interface CBL_Body : NSObject <NSCopying>
{
    @private
    NSData* _json;
    NSDictionary* _object;
    BOOL _error;
}

- (instancetype) initWithProperties: (NSDictionary*)properties;
- (instancetype) initWithArray: (NSArray*)array;
- (instancetype) initWithJSON: (NSData*)json;

+ (instancetype) bodyWithProperties: (id)properties;
+ (instancetype) bodyWithJSON: (NSData*)json;

@property (readonly) BOOL isValidJSON;
@property (readonly) NSData* asJSON;
@property (readonly) NSData* asPrettyJSON;
@property (readonly) NSString* asJSONString;
@property (readonly) id asObject;
@property (readonly) BOOL error;

@property (readonly) NSDictionary* properties;
- (id) objectForKeyedSubscript: (NSString*)key;  // enables subscript access in Xcode 4.4+

@end
