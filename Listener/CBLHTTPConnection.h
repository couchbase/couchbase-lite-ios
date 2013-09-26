//
//  CBLHTTPConnection.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "HTTPConnection.h"
@class CBLListener, CBLResponse;


/** Custom CouchbaseLite subclass of CocoaHTTPServer's HTTPConnection class. */
@interface CBLHTTPConnection : HTTPConnection

@property (readonly) CBLListener* listener;
@property (readonly) NSDictionary* authSession;

-(void)processAuthSession;
-(void)clearAuthSession;
-(void)writeAuthSession:(CBLResponse *)response;
-(NSDictionary *)authenticate:(NSString *)name password:(NSString *)password;
-(NSData *)getSessionHash:(NSString *)name salt:(NSString *)salt timeStamp:(int)timeStamp;
    
@end
