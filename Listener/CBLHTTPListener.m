//
//  CBLHTTPListener.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/7/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLHTTPListener.h"
#import "CBLHTTPConnection.h"
#import "CBLListener+Internal.h"
#import "CBLInternal.h"

#import "HTTPServer.h"
#import "HTTPLogging.h"


@interface CBL_MYDDLogger : DDAbstractLogger
@end


@implementation CBLHTTPListener
{
    CBLHTTPServer* _httpServer;
}

+ (void) initialize {
    if (self == [CBLHTTPListener class]) {
        if (WillLogTo(Listener)) {
            [DDLog addLogger:[[CBL_MYDDLogger alloc] init]];
        }
    }
}

- (instancetype) initWithManager: (CBLManager*)manager port: (UInt16)port {
    self = [super initWithManager: manager port: port];
    if (self) {
        _httpServer = [[CBLHTTPServer alloc] init];
        _httpServer.listener = self;
        _httpServer.cblServer = manager.backgroundServer;
        _httpServer.port = port;
        _httpServer.connectionClass = [CBLHTTPConnection class];
    }
    return self;
}

- (void) setBonjourName: (NSString*)name type: (NSString*)type {
    _httpServer.name = name;
    _httpServer.type = type;
    if (_httpServer.isRunning)
        [_httpServer republishBonjour];
}

- (NSString*) bonjourName {
    return _httpServer.publishedName;
}

- (NSDictionary *)TXTRecordDictionary                   {return _httpServer.TXTRecordDictionary;}
- (void)setTXTRecordDictionary:(NSDictionary *)dict     {_httpServer.TXTRecordDictionary = dict;}

- (BOOL) start: (NSError**)outError {
    return [_httpServer start: outError];
}

- (void) stop {
    [_httpServer stop];
}

- (UInt16) port {
    return _httpServer.listeningPort;
}

- (CBLHTTPServer*)_httpServer {
    return _httpServer;
}

+ (NSSet *)keyPathsForValuesAffectingPort {
    return [NSSet setWithObjects:@"_httpServer.listeningPort", nil];
}


@end



// Adapter to output DDLog messages (from CocoaHTTPServer) via MYUtilities logging.
@implementation CBL_MYDDLogger

- (void) logMessage:(DDLogMessage *)logMessage {
    Log(@"%@", logMessage->logMsg);
}

@end
