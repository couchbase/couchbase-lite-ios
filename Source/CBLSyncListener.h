//
//  CBLSyncListener.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/3/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLManager;


@interface CBLSyncListener : NSObject

- (instancetype) initWithManager: (CBLManager*)manager
                            port: (uint16_t)port;

- (void) setBonjourName: (NSString*)name
                   type: (NSString*)type;

- (BOOL) start: (NSError**)outError;
- (void) stop;

/** The TCP port number that the listener is listening on.
    If the listener has not yet started, this will return 0. */
@property (readonly) UInt16 port;

@end
