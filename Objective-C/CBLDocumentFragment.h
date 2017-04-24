//
//  CBLDocumentFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDictionaryFragment.h"
@class CBLDocument;

@protocol CBLDocumentFragment <NSObject>

/** Checks whether the document exists in the database or not. */
@property (nonatomic, readonly) BOOL exists;

/** Gets the document from the document fragment object. */
@property (nonatomic, readonly, nullable) CBLDocument* document;

@end

@interface CBLDocumentFragment : NSObject <CBLDocumentFragment, CBLDictionaryFragment>

@end
