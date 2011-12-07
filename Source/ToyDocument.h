//
//  CLDocument.h
//  ToyCouch
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright 2010 Jens Alfke. All rights reserved.
//

#import <Cocoa/Cocoa.h>


/** A database document contents, stored as either JSON or an NSDictionary.
    DEPRECATED: This class should get merged into ToyRev. */
@interface ToyDocument : NSObject 
{
    @private
    NSData* _json;
    NSDictionary* _object;
    NSError* _error;
}

- (id) initWithProperties: (NSDictionary*)properties;
- (id) initWithArray: (NSArray*)array;
- (id) initWithJSON: (NSData*)json;

+ (ToyDocument*) documentWithProperties: (id)properties;
+ (ToyDocument*) documentWithJSON: (NSData*)json;

@property (readonly) NSData* asJSON;
@property (readonly) id asObject;
@property (readonly) NSDictionary* properties;
- (id) propertyForKey: (NSString*)key;

/** Error resulting from JSON<->NSDictionary conversion (either way) */
@property (readonly) NSError* error;

@property (readonly) NSString* documentID;
@property (readonly) NSString* revisionID;

@end
