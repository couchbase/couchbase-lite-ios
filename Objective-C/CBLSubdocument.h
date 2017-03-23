//
//  CBLSubdocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLProperties.h"
@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN

/** CBLSubdocument is a suboducment or a nested document with its own set of named properties. 
 In JSON terms it's a nested JSON Map object.
 Like CBLDocument, CBLSubdocument is mutable, so you can make changes in-place. The difference is
 that a subdocument doesn't have its own ID. It's not a first-class entity in the database, 
 it's just a nested object within the document's JSON. It can't be saved individually; changes are 
 persisted when you save its document.*/
@interface CBLSubdocument : CBLProperties

/** The document that the subdocument belong to. */
@property (readonly, nonatomic, nullable) CBLDocument* document;

/** Checks whether the subdocument exists in the database or not. */
@property (readonly, nonatomic) BOOL exists;

/** Create a new subdocument. */
+ (instancetype) subdocument;

/** Initializes a new subdocument. */
- (instancetype) init;

@end

@interface CBLSubdocument (Subscripts)

/** Same as objectForKey: */
- (nullable id) objectForKeyedSubscript: (NSString*)key;

/** Same as setObject:forKey: */
- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key;

@end

NS_ASSUME_NONNULL_END
