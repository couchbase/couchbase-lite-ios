//
//  CBLHTTPConnection.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "HTTPConnection.h"
@class CBLListener;


/** Custom CouchbaseLite subclass of CocoaHTTPServer's HTTPConnection class. */
@interface CBLHTTPConnection : HTTPConnection

@property (readonly) CBLListener* listener;
@property (readonly) NSDictionary* sessionUserProps;
@property (readonly) int sessionTimeStamp;

- (NSString *)authUsername;

-(void)readAuthSession;
-(void)writeAuthSession;
-(void)clearSession;
-(NSDictionary *)authenticate:(NSString *)name password:(NSString *)password;
-(NSData *)sessionHashFor:(NSString *)name salt:(NSString *)salt timeStamp:(int)timeStamp;
    
@end
