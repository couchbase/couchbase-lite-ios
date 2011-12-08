//
//  ToyBody.h
//  ToyCouch
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright 2010 Jens Alfke. All rights reserved.
//

#import <Cocoa/Cocoa.h>


/** A request/response/document body, stored as either JSON or an NSDictionary. */
@interface ToyBody : NSObject 
{
    @private
    NSData* _json;
    NSDictionary* _object;
    BOOL _error;
}

- (id) initWithProperties: (NSDictionary*)properties;
- (id) initWithArray: (NSArray*)array;
- (id) initWithJSON: (NSData*)json;

+ (ToyBody*) bodyWithProperties: (id)properties;
+ (ToyBody*) bodyWithJSON: (NSData*)json;

@property (readonly) NSData* asJSON;
@property (readonly) id asObject;
@property (readonly) BOOL error;

@property (readonly) NSDictionary* properties;
- (id) propertyForKey: (NSString*)key;

@end
