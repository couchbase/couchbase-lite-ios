//
//  CBLChangeListener.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CBLChangeListener : NSObject

@property (nonatomic, readonly, copy) id block;

- (instancetype) initWithBlock: (id)block;

@end
