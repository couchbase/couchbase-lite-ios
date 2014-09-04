//
//  CouchbaseLitePrefix.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#ifdef __OBJC__

#ifdef GNUSTEP
#import "CBLGNUstep.h"
#endif

@import Foundation;

#import "CBLJSON.h"

#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"

#endif // __OBJC__


// Configuration for the sqlite3-unicodesn library:
#define SQLITE_ENABLE_FTS4 
#define SQLITE_ENABLE_FTS4_UNICODE61


// Rename the MYUtilities classes to avoid collisions:
#define MYDynamicObject             CBL_MYDynamicObject

// Rename the GCDAsyncSocket classes to avoid collisions:
#define GCDAsyncSocket              CBL_GCDAsyncSocket
#define GCDAsyncSocketPreBuffer     CBL_GCDAsyncSocketPreBuffer
#define GCDAsyncReadPacket          CBL_GCDAsyncReadPacket
#define GCDAsyncWritePacket         CBL_GCDAsyncWritePacket
#define GCDAsyncSpecialPacket       CBL_GCDAsyncSpecialPacket

// Rename the CocoaLumberjack classes to avoid collisions:
#define DDLog                       CBL_DDLog
#define DDLogMessage                CBL_DDLogMessage
#define DDAbstractLogger            CBL_DDAbstractLogger
#define DDLoggerNode                CBL_DDLoggerNode

// Rename the CocoaHTTPServer classes to avoid collisions:
#define HTTPAsyncFileResponse       CBL_HTTPAsyncFileResponse
#define HTTPAuthenticationRequest   CBL_HTTPAuthenticationRequest
#define HTTPConfig                  CBL_HTTPConfig
#define HTTPConnection              CBL_HTTPConnection
#define HTTPDataResponse            CBL_HTTPDataResponse
#define HTTPDynamicFileResponse     CBL_HTTPDynamicFileResponse
#define HTTPFileResponse            CBL_HTTPFileResponse
#define HTTPMessage                 CBL_HTTPMessage
#define HTTPRedirectResponse        CBL_HTTPRedirectResponse
#define HTTPServer                  CBL_HTTPServer

// Rename the oathconsumer classes to avoid collisions:
#define OAConsumer                  CBL_OAConsumer
#define OAMutableURLRequest         CBL_OAMutableURLRequest
#define OAPlaintextSignatureProvider  CBL_OAPlaintextSignatureProvider
#define OARequestParameter          CBL_OARequestParameter
#define OAToken                     CBL_OAToken

// Rename the WebScket classes to avoid collisions:
#define WebSocket                   CBL_WebSocket
#define WebSocketClient             CBL_WebSocketClient
#define WebSocketHTTPLogic          CBL_WebSocketHTTPLogic
