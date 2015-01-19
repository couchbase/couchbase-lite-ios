//
//  CBL_SQLiteStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/15.
//
//

#import "CBL_Storage.h"
@class CBL_FMDatabase;


@interface CBL_SQLiteStorage : NSObject <CBL_Storage>

@property (readonly, nonatomic) CBL_FMDatabase* fmdb;
@property (readonly, nonatomic) CBLStatus lastDbStatus;
@property (readonly, nonatomic) CBLStatus lastDbError;

- (BOOL) runStatements: (NSString*)statements error: (NSError**)outError;

- (NSDictionary*) documentPropertiesFromJSON: (NSData*)json
                                       docID: (NSString*)docID
                                       revID: (NSString*)revID
                                     deleted: (BOOL)deleted
                                    sequence: (SequenceNumber)sequence
                                     options: (CBLContentOptions)options;

@end
