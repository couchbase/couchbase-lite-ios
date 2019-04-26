//
//  CBLConflict+Internal.h
//  CBL ObjC
//
//  Created by Jayahari Vavachan on 4/26/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

#import "CBLConflict.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLConflict (Internal)

- (instancetype) initWithLocalDocument: (CBLDocument*)localDoc
                        remoteDocument: (CBLDocument*)remoteDoc;

@end

NS_ASSUME_NONNULL_END
