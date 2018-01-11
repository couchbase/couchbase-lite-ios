//
//  CBLQueryMeta.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLQueryMeta is a factory class for creating the expressions that refers to
 the metadata properties of the document.
 */
@interface CBLQueryMeta : NSObject

/**
 Document ID expression.

 @return The document ID expression.
 */
+ (CBLQueryExpression*) id;

/**
 Document ID expression.

 @param alias The data source alias name.
 @return The document ID expression.
 */
+ (CBLQueryExpression*) idFrom: (nullable NSString*)alias;

/**
 Sequence number expression. The sequence number indicates how recently
 the document has been changed. If one document's `sequence` is greater
 than another's, that means it was changed more recently.

 @return The sequence number expression.
 */
+ (CBLQueryExpression*) sequence;

/**
 Sequence number expression. The sequence number indicates how recently
 the document has been changed. If one document's `sequence` is greater
 than another's, that means it was changed more recently.

 @param alias The data source alias name.
 @return The sequence number expression.
 */
+ (CBLQueryExpression*) sequenceFrom: (nullable NSString*)alias;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
