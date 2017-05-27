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

NSString* const kCBLErrorDomain = @"CouchbaseLite";


static bool toC4Error(int cfNetworkErrorCode, C4Error *outError);
static bool toCFNetworkError(C4Error err, int *outCode);


static NSDictionary* statusDesc = @{
    @(kCBLStatusForbidden) : @"forbidden",
    @(kCBLStatusNotFound)  : @"not found"
};


BOOL convertError(const C4Error &c4err, NSError** outError) {
    NSCAssert(c4err.code != 0 && c4err.domain != 0, @"No C4Error");
    static NSString* const kNSErrorDomains[kC4MaxErrorDomainPlus1] =
        {nil, @"LiteCore", NSPOSIXErrorDomain, @"3", @"SQLite", @"Fleece", @"Network", @"WebSocket"};
    if (outError) {
        NSString* msgStr = sliceResult2string(c4error_getMessage(c4err));
        NSString* domain = kNSErrorDomains[c4err.domain];
        int code = c4err.code;

        if (toCFNetworkError(c4err, &code))
            domain = (__bridge id)kCFErrorDomainCFNetwork;

        *outError = [NSError errorWithDomain: domain code: code
                                    userInfo: @{NSLocalizedDescriptionKey: msgStr}];
    }
    return NO;
}


BOOL convertError(const FLError &flErr, NSError** outError) {
    NSCAssert(flErr != 0, @"No C4Error");
    if (outError)
        *outError = [NSError errorWithDomain: FLErrorDomain code: flErr userInfo: nil];
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
            toC4Error(code, &c4err);
        }
    }
    *outError = c4error_make(c4err.domain, c4err.code, c4str(message));
}


BOOL createError(CBLStatus status,  NSError** outError) {
    return createError(status, nil, outError);
}


BOOL createError(CBLStatus status,  NSString* desc, NSError** outError) {
    if (outError) {
        if (!desc)
            desc = statusDesc[@(status)];
        NSDictionary* info = @{ NSLocalizedFailureReasonErrorKey: desc,
                                NSLocalizedDescriptionKey: desc };
        *outError = [NSError errorWithDomain: kCBLErrorDomain  code: status userInfo: info];
    }
    return NO;
}


// Maps CFNetworkErrors to C4Errors ... see <CFNetwork/CFNetworkErrors.h>
static const struct {int code; C4Error c4err;} kCFNetworkErrorMap[] = {
    {kCFErrorHTTPConnectionLost,                {POSIXDomain, ECONNRESET}},
    {kCFURLErrorCannotConnectToHost,            {POSIXDomain, ECONNREFUSED}},
    {kCFURLErrorNetworkConnectionLost,          {POSIXDomain, ECONNRESET}},
    {kCFHostErrorHostNotFound,                  {NetworkDomain, kC4NetErrUnknownHost}},
    {kCFURLErrorTimedOut,                       {NetworkDomain, kC4NetErrTimeout}},
    {kCFURLErrorHTTPTooManyRedirects,           {NetworkDomain, kC4NetErrTooManyRedirects}},
    {kCFErrorHTTPRedirectionLoopDetected,       {NetworkDomain, kC4NetErrTooManyRedirects}},
    {kCFErrorHTTPBadURL,                        {NetworkDomain, kC4NetErrInvalidURL}},
    {kCFURLErrorSecureConnectionFailed,         {NetworkDomain, kC4NetErrTLSHandshakeFailed}},
    {kCFURLErrorServerCertificateHasBadDate,    {NetworkDomain, kC4NetErrTLSCertExpired}},
    {kCFURLErrorServerCertificateNotYetValid,   {NetworkDomain, kC4NetErrTLSCertExpired}},
    {kCFURLErrorServerCertificateUntrusted,     {NetworkDomain, kC4NetErrTLSCertUntrusted}},
    {kCFURLErrorServerCertificateHasUnknownRoot,{NetworkDomain, kC4NetErrTLSCertUntrusted}},
    {kCFURLErrorClientCertificateRequired,      {NetworkDomain, kC4NetErrTLSClientCertRequired}},
    {kCFURLErrorClientCertificateRejected,      {NetworkDomain, kC4NetErrTLSClientCertRejected}},
    {kCFErrorHTTPBadProxyCredentials,           {WebSocketDomain, 407}},
    {0}
    // This list is incomplete but covers most of what will actually occur
};


static bool toC4Error(int code, C4Error *outError) {
    for (int i = 0; kCFNetworkErrorMap[i].code; ++i) {
        if (kCFNetworkErrorMap[i].code == code) {
            *outError = kCFNetworkErrorMap[i].c4err;
            return true;
        }
    }
    return false;
}


static bool toCFNetworkError(C4Error err, int *outCode) {
    for (auto map = kCFNetworkErrorMap; map->code; ++map) {
        if (map->c4err.code == err.code && map->c4err.domain == err.domain) {
            *outCode = map->code;
            return true;
        }
    }
    return false;
}
