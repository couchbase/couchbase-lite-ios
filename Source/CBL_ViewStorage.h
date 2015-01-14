//
//  CBL_ViewStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/15.
//
//

#import "CBL_Storage.h"
@protocol CBL_ViewStorageDelegate;


@protocol CBL_ViewStorage <NSObject>

@property (readonly) NSString* name;
@property (nonatomic, weak) id<CBL_ViewStorageDelegate> delegate;

- (void) close;
- (void) deleteIndex;
- (void) deleteView;

- (CBLStatus) updateIndexes: (NSArray*)views; // array of CBL_ViewStorage

@property (readonly) NSUInteger totalRows;
@property (readonly) SequenceNumber lastSequenceIndexed;
@property (readonly) SequenceNumber lastSequenceChangedAt;

- (CBLQueryIteratorBlock) regularQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus;
- (CBLQueryIteratorBlock) reducedQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus;
- (CBLQueryIteratorBlock) fullTextQueryWithOptions: (CBLQueryOptions*)options
                                            status: (CBLStatus*)outStatus;

#if DEBUG
- (NSArray*) dump;  // Just for unit tests & debugging. Returns array of {key, value, seq}
#endif

@end




@protocol CBL_QueryRowStorage <NSObject>
- (BOOL) rowValueIsEntireDoc: (NSData*)valueData;
- (id) parseRowValue: (NSData*)valueData;
- (NSDictionary*) documentPropertiesWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus;
- (NSData*) fullTextForDocument: (NSString*)docID
                       sequence: (SequenceNumber)sequenceNumber
                     fullTextID: (unsigned)fullTextID;
@end




@interface CBL_ForestDBViewStorage : NSObject <CBL_ViewStorage>

// internal:
- (instancetype) initWithDBStorage: (CBL_ForestDBStorage*)dbStorage
                              name: (NSString*)name
                            create: (BOOL)create;
+ (NSString*) fileNameToViewName: (NSString*)fileName;

@end




@protocol CBL_ViewStorageDelegate <NSObject>

@property (readonly) CBLMapBlock mapBlock;
@property (readonly) CBLReduceBlock reduceBlock;
@property (readonly) NSString* mapVersion;

@end