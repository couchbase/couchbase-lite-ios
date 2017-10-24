//
//  CBLDocumentFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLMutableDictionaryFragment.h"
@class CBLMutableDocument;

/** 
 CBLMutableDocumentFragment provides access to a document object. CBLMutableDocumentFragment also provides
 subscript access by either key or index to the data values of the document which are
 wrapped by CBLMutableFragment objects.
 */
@interface CBLMutableDocumentFragment : NSObject <CBLMutableDictionaryFragment>

/** Checks whether the document exists in the database or not. */
@property (nonatomic, readonly) BOOL exists;

/** Gets the document from the document fragment object. */
@property (nonatomic, readonly, nullable) CBLMutableDocument* document;

@end
