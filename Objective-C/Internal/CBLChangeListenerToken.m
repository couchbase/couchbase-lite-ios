//
//  CBLChangeListenerToken.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLChangeListenerToken.h"

@implementation CBLChangeListenerToken

@synthesize listener=_listener;
@synthesize queue=_queue;


- (instancetype) initWithListener: (id)listener
                            queue: (nullable dispatch_queue_t)queue
{
    self = [super init];
    if (self) {
        _listener = listener;
        _queue = queue;
    }
    return self;
}


- (dispatch_queue_t) queue {
    if (_queue)
        return _queue;
    return dispatch_get_main_queue();
}


@end
