//
//  CBL_ForestDBStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/15.
//
//

#import "CBL_Storage.h"


@interface CBL_ForestDBStorage : NSObject <CBL_Storage>
@property (nonatomic, readonly) void* forestDatabase; // really forestdb::Database*
@end
