//
//  CBLStatus.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLStatus.h"
#import "CBLCoreBridge.h"
#import <netdb.h>

NSErrorDomain const CBLErrorDomain          = @"CouchbaseLite";

static NSErrorDomain const SQLiteErrorDomain    = @"CouchbaseLite.SQLite";
static NSErrorDomain const FleeceErrorDomain    = @"CouchbaseLite.Fleece";


static bool cfNetworkToC4Error(int cfNetworkErrorCode, C4Error *outError);
static bool c4ToCFNetworkError(C4Error err, NSString* __autoreleasing *outDomain, int *outCode);


BOOL convertError(const C4Error &c4err, NSError** outError) {
    NSCAssert(c4err.code != 0 && c4err.domain != 0, @"No C4Error");
    static NSErrorDomain const kNSErrorDomains[kC4MaxErrorDomainPlus1] =
        {nil, CBLErrorDomain, NSPOSIXErrorDomain, nil, SQLiteErrorDomain,
         FleeceErrorDomain, nil, CBLErrorDomain};
    if (outError) {
        NSString* msgStr = sliceResult2string(c4error_getMessage(c4err));
        NSString* domain;
        int code;

        if (!c4ToCFNetworkError(c4err, &domain, &code)) {
            domain = kNSErrorDomains[c4err.domain];
            code = c4err.code;
            if (c4err.domain == WebSocketDomain)
                code += CBLErrorHTTPBase;   // WebSocket and HTTP statuses are offset by 10000
        }

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


static bool c4ToCFNetworkError(C4Error err, NSString* __autoreleasing *outDomain, int *outCode) {
    for (auto map = kCFNetworkErrorMap; map->code; ++map) {
        if (map->c4err.code == err.code && map->c4err.domain == err.domain) {
            *outCode = map->code;
            // NSURLDomain is more commonly seen in Cocoa APIs, but kCFErrorDomainCFNetwork is a
            // superset with more error codes. Use the former if the code is in range:
            if (map->code <= -995 && map->code >= -3007)
                *outDomain = NSURLErrorDomain;
            else
                *outDomain = (__bridge id)kCFErrorDomainCFNetwork;
            return true;
        }
    }
    if (err.domain == NetworkDomain) {
        // Make sure that all NetworkDomain errors are converted
        C4Warn("Unable to map C4Error(NetworkDomain,%d) to a specific NSURLErrorDomain code", err.code);
        *outCode = NSURLErrorUnknown;
        *outDomain = NSURLErrorDomain;
        return true;
    }
    return false;
}
