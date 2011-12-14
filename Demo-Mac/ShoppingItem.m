//
//  ShoppingItem.m
//  CouchCocoa
//
//  Created by Jens Alfke on 8/26/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ShoppingItem.h"

@implementation ShoppingItem

@dynamic check, text, created_at;

- (NSDictionary*) propertiesToSave {
    if (self.created_at == nil)
        self.created_at = [NSDate date];
    return [super propertiesToSave];
}

@end
