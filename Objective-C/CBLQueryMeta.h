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

/** CBLQueryMeta is a factory class for creating the expressions that refer to 
    the metadata properties of the document. */
@interface CBLQueryMeta : NSObject

/** An expression refering to the ID of the document. */
@property (nonatomic, readonly) CBLQueryExpression* documentID;

/** An expression refering to the sequence number of the document. 
    The sequence number indicates how recently the document has been changed. If one document's
    `sequence` is greater than another's, that means it was changed more recently. */
@property (nonatomic, readonly) CBLQueryExpression* sequence;

@end

NS_ASSUME_NONNULL_END
