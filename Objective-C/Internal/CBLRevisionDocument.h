//
//  CBLRevisionDocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/29/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLDocument.h"
#import "fleece/Fleece.h"
@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface CBLRevisionDocument : CBLDocument

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (C4String)documentID
                            flags: (C4RevisionFlags)flags
                             body: (FLDict)body;
@end

NS_ASSUME_NONNULL_END
