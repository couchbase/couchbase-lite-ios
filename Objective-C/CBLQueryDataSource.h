//
//  CBLQueryDataSource.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryDatabase, CBLDatabase;


NS_ASSUME_NONNULL_BEGIN


@interface CBLQueryDataSource : NSObject

- (instancetype) init NS_UNAVAILABLE;

+ (CBLQueryDatabase*) database: (CBLDatabase*)database;

@end


@interface CBLQueryDatabase : CBLQueryDataSource

- (instancetype) init NS_UNAVAILABLE;

//TODO (Will implement this when join is supported):
// - (CBLQueryDataSource *) as:(NSString *)as;

@end


NS_ASSUME_NONNULL_END


