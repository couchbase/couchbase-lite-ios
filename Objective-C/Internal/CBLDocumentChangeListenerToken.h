//
//  CBLDocumentChangeListenerToken.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLChangeListenerToken.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLDocumentChangeListenerToken : CBLChangeListenerToken

@property (nonatomic, readonly, copy) NSString* documentID;

- (instancetype) initWithDocumentID: (NSString*)documentID
                           listener: (id)listener
                              queue: (nullable dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
