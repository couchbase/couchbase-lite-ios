//
//  CBL_Body.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBL_RevID;


/** A request/response/document body, stored as either JSON or an NSDictionary. */
@interface CBL_Body : NSObject <NSCopying>

- (instancetype) initWithProperties: (NSDictionary*)properties;
- (instancetype) initWithArray: (NSArray*)array;
- (instancetype) initWithJSON: (NSData*)json;

+ (instancetype) bodyWithProperties: (NSDictionary*)properties;
+ (instancetype) bodyWithJSON: (NSData*)json;

 /** Creates a body from JSON data, inserting "_id", _"rev" and "_deleted" properties based on the
     input parameters. */
- (instancetype) initWithJSON: (NSData*)json
                  addingDocID: (NSString*)docID
                        revID: (CBL_RevID*)revID
                      deleted: (BOOL)deleted;

@property (readonly) BOOL isValidJSON;
@property (readonly) NSData* asJSON;
@property (readonly) NSData* asPrettyJSON;
@property (readonly) NSString* asJSONString;
@property (readonly) id asObject;
@property (readonly) BOOL error;

@property (readonly) NSDictionary* properties;
- (id) objectForKeyedSubscript: (NSString*)key;  // enables subscript access in Xcode 4.4+

/** Removes the receiver's cached NSDictionary, first converting it to JSON if necessary.
    This has no visible effect, but saves some memory. */
- (BOOL) compact;

@end



@interface NSDictionary (CBL_Body)
@property (readonly) NSString* cbl_id;
@property (readonly) CBL_RevID* cbl_rev;
@property (readonly) NSString* cbl_revStr;
@property (readonly) BOOL cbl_deleted;
@property (readonly) NSDictionary* cbl_attachments;
@end

@interface NSMutableDictionary (CBL_Body)
@property (readwrite) CBL_RevID* cbl_rev;
@property (readwrite) NSString* cbl_revStr;
- (void) cbl_setID: (NSString*)docID rev: (CBL_RevID*)revID;
- (void) cbl_setID: (NSString*)docID revStr: (NSString*)revIDStr;
@end
