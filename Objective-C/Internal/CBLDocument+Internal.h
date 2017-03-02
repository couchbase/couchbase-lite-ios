//
//  CBLDocument+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//
#import "CBLDocument.h"
#import "CBLDatabase.h"


NS_ASSUME_NONNULL_BEGIN

@interface CBLDocument ()

@property (weak, nonatomic, nullable) id swiftDocument;

- (instancetype) initWithDatabase: (CBLDatabase*)db
                            docID: (NSString*)docID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError;

- (void)changedExternally;
@end

NS_ASSUME_NONNULL_END
