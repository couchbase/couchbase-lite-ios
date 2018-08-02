//
//  CBLStatus.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLStatus.h"
#import "CBLCoreBridge.h"
#import <netdb.h>

NSErrorDomain const CBLErrorDomain          = @"CouchbaseLite";

static NSErrorDomain const SQLiteErrorDomain    = @"CouchbaseLite.SQLite";
static NSErrorDomain const FleeceErrorDomain    = @"CouchbaseLite.Fleece";


static bool cfNetworkToC4Error(int cfNetworkErrorCode, C4Error *outError);
static bool osStatusToC4Error(OSStatus, C4Error *outError);


BOOL convertError(const C4Error &c4err, NSError** outError) {
    NSCAssert(c4err.code != 0 && c4err.domain != 0, @"No C4Error");
    static NSErrorDomain const kNSErrorDomains[kC4MaxErrorDomainPlus1] =
        {nil, CBLErrorDomain, NSPOSIXErrorDomain, SQLiteErrorDomain,
         FleeceErrorDomain, CBLErrorDomain, CBLErrorDomain};
    if (outError) {
        NSString* msgStr = sliceResult2string(c4error_getMessage(c4err));
        NSString* domain = kNSErrorDomains[c4err.domain];
        int code = c4err.code;
        if (c4err.domain == NetworkDomain)
            code += CBLErrorNetworkBase; // Network error statuses are offset by 5000
        else if (c4err.domain == WebSocketDomain)
            code += CBLErrorHTTPBase;    // WebSocket and HTTP statuses are offset by 10000

        if (domain == nil) {
            C4Warn("Unable to map C4Error(%d,%d) to an NSError", c4err.domain, c4err.code);
            domain = CBLErrorDomain;
            code = CBLErrorUnexpectedError;
        }

        *outError = [NSError errorWithDomain: domain code: code
                                    userInfo: @{NSLocalizedDescriptionKey: msgStr}];
    }
    return NO;
}


BOOL convertError(const FLError &flErr, NSError** outError) {
    NSCAssert(flErr != 0, @"No C4Error");
    if (outError)
        *outError = [NSError errorWithDomain: FleeceErrorDomain code: flErr userInfo: nil];
    return NO;
}


void convertError(NSError* error, C4Error *outError) {
    C4Error c4err = {LiteCoreDomain, kC4ErrorRemoteError};
    NSString* domain = error.domain;
    const char *message = error.localizedFailureReason.UTF8String ?: "";
    int code = (int)error.code;
    if ([domain isEqualToString: NSPOSIXErrorDomain]) {
        c4err = {POSIXDomain, (int)code};
    } else if ([domain isEqualToString: NSURLErrorDomain]
               || [domain isEqualToString: (__bridge id)kCFErrorDomainCFNetwork]) {
        if (code == kCFHostErrorUnknown) {
            code = [error.userInfo[(__bridge id)kCFGetAddrInfoFailureKey] intValue];
            c4err.domain = NetworkDomain;
            if (code == HOST_NOT_FOUND || code == EAI_NONAME)
                c4err.code = kC4NetErrUnknownHost;
            else
                c4err.code = kC4NetErrDNSFailure;
        } else {
            cfNetworkToC4Error(code, &c4err);
        }
    } else if ([domain isEqualToString: NSOSStatusErrorDomain]) {
        if (!osStatusToC4Error(code, &c4err)) {
            if (code >= -9899 && code <= -9800)
                c4err = {NetworkDomain, kC4NetErrTLSHandshakeFailed};   // SecureTransport errors
        }
    }
    *outError = c4error_make(c4err.domain, c4err.code, c4str(message));
}


BOOL createError(int status,  NSError** outError) {
    return createError(status, nil, outError);
}


BOOL createError(int status,  NSString* desc, NSError** outError) {
    if (outError) {
        if (!desc) {
            C4StringResult msg = c4error_getMessage({LiteCoreDomain, status});
            desc = slice2string({msg.buf, msg.size});
            c4slice_free(msg);
        }
        NSDictionary* info = @{ NSLocalizedFailureReasonErrorKey: desc,
                                NSLocalizedDescriptionKey: desc };
        *outError = [NSError errorWithDomain: CBLErrorDomain code: status userInfo: info];
    }
    return NO;
}


struct ErrorMapping {int code; C4Error c4err;};


static bool mapToC4Error(int code, const ErrorMapping map[], C4Error *outError) {
    for (int i = 0; map[i].code; ++i) {
        if (map[i].code == code) {
            *outError = map[i].c4err;
            return true;
        }
    }
    return false;
}


static bool cfNetworkToC4Error(int code, C4Error *outError) {
    // Maps CFNetworkErrors <-> C4Errors ... see <CFNetwork/CFNetworkErrors.h>
    static const ErrorMapping kCFNetworkErrorMap[] = {
        {kCFErrorHTTPConnectionLost,                {POSIXDomain, ECONNRESET}},
        {kCFURLErrorCannotConnectToHost,            {POSIXDomain, ECONNREFUSED}},
        {kCFURLErrorNetworkConnectionLost,          {POSIXDomain, ECONNRESET}},
        {kCFURLErrorDNSLookupFailed,                {NetworkDomain, kC4NetErrDNSFailure}},
        {kCFHostErrorHostNotFound,                  {NetworkDomain, kC4NetErrUnknownHost}},
        {kCFURLErrorTimedOut,                       {NetworkDomain, kC4NetErrTimeout}},
        {kCFErrorHTTPBadURL,                        {NetworkDomain, kC4NetErrInvalidURL}},
        {kCFURLErrorHTTPTooManyRedirects,           {NetworkDomain, kC4NetErrTooManyRedirects}},
        {kCFErrorHTTPRedirectionLoopDetected,       {NetworkDomain, kC4NetErrTooManyRedirects}},
        {kCFURLErrorSecureConnectionFailed,         {NetworkDomain, kC4NetErrTLSHandshakeFailed}},
        {kCFURLErrorServerCertificateHasBadDate,    {NetworkDomain, kC4NetErrTLSCertExpired}},
        {kCFURLErrorServerCertificateNotYetValid,   {NetworkDomain, kC4NetErrTLSCertExpired}},
        {kCFURLErrorServerCertificateUntrusted,     {NetworkDomain, kC4NetErrTLSCertUntrusted}},
        {kCFURLErrorClientCertificateRequired,      {NetworkDomain, kC4NetErrTLSClientCertRequired}},
        {kCFURLErrorClientCertificateRejected,      {NetworkDomain, kC4NetErrTLSClientCertRejected}},
        {kCFURLErrorServerCertificateHasUnknownRoot,{NetworkDomain, kC4NetErrTLSCertUnknownRoot}},
        {kCFURLErrorRedirectToNonExistentLocation,  {NetworkDomain, kC4NetErrInvalidRedirect}},
        {kCFErrorHTTPRedirectionLoopDetected,       {NetworkDomain, kC4NetErrInvalidRedirect}},
        {kCFURLErrorHTTPTooManyRedirects,           {NetworkDomain, kC4NetErrInvalidRedirect}},
        {kCFErrorHTTPBadProxyCredentials,           {WebSocketDomain, 407}},
        {0}
        // This list is incomplete but covers most of what will actually occur
    };
    return mapToC4Error(code, kCFNetworkErrorMap, outError);
}


static bool osStatusToC4Error(OSStatus code, C4Error *outError) {
    // Maps OSStatusErrorDomain errors <-> C4Errors ... see <Security/SecureTransport.h>
    static const ErrorMapping kCFNetworkErrorMap[] = {
        {errSSLXCertChainInvalid,                   {NetworkDomain, kC4NetErrTLSCertUnknownRoot}},
        {errSSLBadCert,                             {NetworkDomain, kC4NetErrTLSCertUntrusted}},
        {errSSLUnknownRootCert,                     {NetworkDomain, kC4NetErrTLSCertUnknownRoot}},
        {errSSLNoRootCert,                          {NetworkDomain, kC4NetErrTLSCertUnknownRoot}},
        {errSSLCertExpired,                         {NetworkDomain, kC4NetErrTLSCertExpired}},
        {errSSLCertNotYetValid,                     {NetworkDomain, kC4NetErrTLSCertExpired}},
        {0}
        // This list is incomplete. Any OSStatus in [-9865...-9800] is a TLS error.
    };
    return mapToC4Error(code, kCFNetworkErrorMap, outError);
}
