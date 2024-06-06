//
//  CBLQueryIndex+Internal.h
//  CouchbaseLite
//
//  Created by Vlad Velicu on 03/06/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CouchbaseLite/CBLCollection.h>
#import <CouchbaseLite/CBLQueryIndex.h>
#import "c4Index.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryIndex () {
    
}

@property (nonatomic, readonly) C4Index* c4index;

- (id) mutex;

- (instancetype) initWithIndex: (C4Index*) index
                          name: (NSString*) name
                    collection: (CBLCollection*) collection;
@end



NS_ASSUME_NONNULL_END
