//
//  CBLBlipReplicator.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 5/1/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBL_Replicator.h"


@interface CBLBlipReplicator : NSObject <CBL_Replicator>

//@property (readonly) NSProgress* progress;
//@property (readonly) NSArray* nestedProgress;

- (BOOL) validateServerTrust: (SecTrustRef)trust;

@end
