//
//  CBLSubdocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDictionary.h"
#import "CBLReadOnlySubdocument.h"

NS_ASSUME_NONNULL_BEGIN

/** CBLSuboducument is a suboducment or a nested document with its own set of named properties. 
    In JSON terms it's a nested JSON Map object.
    Like CBLDocument, CBLSubdocument is mutable, so you can make changes in-place. 
    The difference is that a subdocument doesn't have its own ID. It's not a first-class entity 
    in the database, it's just a nested object within the document's JSON. It can't be saved 
    individually; changes are persisted when you save its document. */
@interface CBLSubdocument : CBLReadOnlySubdocument <CBLDictionary>

/** Creates a new empty CBLSubdocument object.
    @result the CBLSubdocument object. */
+ (instancetype) subdocument;

/** Initializes a new empty CBLSubdocument object.
    @result the CBLSubdocument object. */
- (instancetype) init;

/** Initialzes a new CBLSubdocument object with dictionary content. Allowed value types are NSArray,
    NSDate, NSDictionary, NSNumber, NSNull, NSString, CBLArray, CBLBlob, CBLSubdocument.
    The NSArrays and NSDictionaries must contain only the above types.*/
- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary;

@end

NS_ASSUME_NONNULL_END
