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


// Maps CFNetworkErrors <-> C4Errors ... see <CFNetwork/CFNetworkErrors.h>
static const struct {int code; C4Error c4err;} kCFNetworkErrorMap[] = {
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


static bool cfNetworkToC4Error(int code, C4Error *outError) {
    for (int i = 0; kCFNetworkErrorMap[i].code; ++i) {
        if (kCFNetworkErrorMap[i].code == code) {
            *outError = kCFNetworkErrorMap[i].c4err;
            return true;
        }
    }
    return false;
}
