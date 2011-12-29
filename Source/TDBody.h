//
//  TDBody.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** A request/response/document body, stored as either JSON or an NSDictionary. */
@interface TDBody : NSObject 
{
    @private
    NSData* _json;
    NSDictionary* _object;
    BOOL _error;
}

- (id) initWithProperties: (NSDictionary*)properties;
- (id) initWithArray: (NSArray*)array;
- (id) initWithJSON: (NSData*)json;

+ (TDBody*) bodyWithProperties: (id)properties;
+ (TDBody*) bodyWithJSON: (NSData*)json;

@property (readonly) BOOL isValidJSON;
@property (readonly) NSData* asJSON;
@property (readonly) NSData* asPrettyJSON;
@property (readonly) NSString* asJSONString;
@property (readonly) id asObject;
@property (readonly) BOOL error;

@property (readonly) NSDictionary* properties;
- (id) propertyForKey: (NSString*)key;

@end
