//
//  CBLDocumentChangeListener.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLChangeListener.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLDocumentChangeListener : CBLChangeListener

@property (nonatomic, readonly, copy) NSString* documentID;

- (instancetype) initWithDocumentID: (NSString*)documentID
                          withBlock: (id)block;

@end

NS_ASSUME_NONNULL_END
