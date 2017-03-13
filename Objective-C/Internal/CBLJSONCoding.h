//
//  CBLJSONCoding.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN


@protocol CBLJSONCoding <NSObject>

@property (readonly, nonatomic) NSDictionary* jsonRepresentation;

@end


NS_ASSUME_NONNULL_END
