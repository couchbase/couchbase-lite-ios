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

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Workaround for building with older (pre-iOS8/10.10) SDKs that don't define this macro:
#ifndef NS_DESIGNATED_INITIALIZER
#define NS_DESIGNATED_INITIALIZER
#endif

#import "CBLJSON.h"

//#define MY_DISABLE_LOGGING    // Uncomment this to prevent Log calls from generating any code

#define MYERRORUTILS_USE_SECURITY_API 1     // Tell MYErrorUtils it can look up Security messages

#import "CollectionUtils.h"
#import "MYLogging.h"
#import "Test.h"

#ifdef __cplusplus
}
#endif


// Rename the GCDAsyncSocket classes to avoid collisions:
#define GCDAsyncSocket              CBL_GCDAsyncSocket
#define GCDAsyncSocketPreBuffer     CBL_GCDAsyncSocketPreBuffer
#define GCDAsyncReadPacket          CBL_GCDAsyncReadPacket
#define GCDAsyncWritePacket         CBL_GCDAsyncWritePacket
#define GCDAsyncSpecialPacket       CBL_GCDAsyncSpecialPacket

#define GCDAsyncSocketErrorDomain   CBL_GCDAsyncSocketErrorDomain
#define GCDAsyncSocketException     CBL_GCDAsyncSocketException
#define GCDAsyncSocketQueueName     CBL_GCDAsyncSocketQueueName
#define GCDAsyncSocketThreadName    CBL_GCDAsyncSocketThreadName
#define GCDAsyncSocketSSLCipherSuites       CBL_GCDAsyncSocketSSLCipherSuites
#define GCDAsyncSocketSSLProtocolVersionMax CBL_GCDAsyncSocketSSLProtocolVersionMax
#define GCDAsyncSocketSSLProtocolVersionMin CBL_GCDAsyncSocketSSLProtocolVersionMin

#define GCDAsyncSocketManuallyEvaluateTrust CBL_GCDAsyncSocketManuallyEvaluateTrust
#define GCDAsyncSocketUseCFStreamForTLS     CBL_GCDAsyncSocketUseCFStreamForTLS
#define GCDAsyncSocketSSLPeerID             CBL_GCDAsyncSocketSSLPeerID
#define GCDAsyncSocketSSLSessionOptionFalseStart        CBL_GCDAsyncSocketSSLSessionOptionFalseStart
#define GCDAsyncSocketSSLSessionOptionSendOneByteRecord CBL_GCDAsyncSocketSSLSessionOptionSendOneByteRecord

// Rename the CocoaLumberjack classes to avoid collisions:
#define DDLog                       CBL_DDLog
#define DDLogMessage                CBL_DDLogMessage
#define DDAbstractLogger            CBL_DDAbstractLogger
#define DDLoggerNode                CBL_DDLoggerNode
#define DDExtractFileNameWithoutExtension CBL_DDExtractFileNameWithoutExtension
#define DDUnionRange                CBL_DDUnionRange
#define DDIntersectionRange         CBL_DDIntersectionRange
#define DDStringFromRange           CBL_DDStringFromRange
#define DDRangeFromString           CBL_DDRangeFromString
#define DDRangeCompare              CBL_DDRangeCompare

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

// Rename the WebSocket classes to avoid collisions:
#define WebSocket                   CBL_WebSocket
#define WebSocketClient             CBL_WebSocketClient
#define WebSocketHTTPLogic          CBL_WebSocketHTTPLogic
#define WebSocketErrorDomain        CBL_WebSocketErrorDomain

#endif // __OBJC__
