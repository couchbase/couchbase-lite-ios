//
//  CLDocument.h
//  ToyCouch
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright 2010 Jens Alfke. All rights reserved.
//

#import <Cocoa/Cocoa.h>



/** A single JSON data object. */
@interface CLDocument : NSObject 
{
    @private
    NSData* _json;
    NSDictionary* _properties;
    NSError* _error;
}

- (id) initWithProperties: (NSDictionary*)properties;
- (id) initWithJSON: (NSData*)json;

@property (readonly) NSData* asJSON;
@property (readonly) NSDictionary* properties;
- (id) propertyForKey: (NSString*)key;

@property (readonly) NSError* error;

@property (readonly) NSString* documentID;
@property (readonly) NSString* revisionID;

@end
