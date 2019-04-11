//
//  MiscCppTest.mm
//  CBL ObjC Tests
//
//  Created by Jayahari Vavachan on 4/10/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLStatus.h"

@interface MiscCppTest : CBLTestCase

@end

@implementation MiscCppTest

#pragma mark - CBLStatus

- (void) testConvertErrorNSErrorToC4ErrorNSURLError {
    NSError* error = [NSError errorWithDomain: NSURLErrorDomain
                                         code: kCFHostErrorHostNotFound
                                     userInfo: nil];
    C4Error c4err;
    convertError(error, &c4err);
    AssertEqual(c4err.domain, NetworkDomain);
    AssertEqual(c4err.code, kC4NetErrUnknownHost);
    
    error = [NSError errorWithDomain: NSURLErrorDomain
                                code: kCFErrorHTTPConnectionLost
                            userInfo: nil];
    convertError(error, &c4err);
    AssertEqual(c4err.domain, POSIXDomain);
    AssertEqual(c4err.code, ECONNRESET);
}

- (void) testConvertErrorNSErrorToC4ErrorOSStatusError {
    C4Error c4err;
    NSError* error = [NSError errorWithDomain: NSOSStatusErrorDomain
                                         code: errSSLCertExpired
                                     userInfo: nil];
    convertError(error, &c4err);
    AssertEqual(c4err.domain, NetworkDomain);
    AssertEqual(c4err.code, kC4NetErrTLSCertExpired);
    
    // error code between -9899 & -9800
    error = [NSError errorWithDomain: NSOSStatusErrorDomain
                                code: errSSLPeerInternalError
                            userInfo: nil];
    convertError(error, &c4err);
    AssertEqual(c4err.domain, NetworkDomain);
    AssertEqual(c4err.code, kC4NetErrTLSHandshakeFailed);
}

- (void) testConvertErrorNSErrorToC4ErrorUndefinedError {
    C4Error c4err;
    NSError* error = [NSError errorWithDomain: NSOSStatusErrorDomain
                                         code: errSSLPeerInternalError
                                     userInfo: nil];
    convertError(error, &c4err);
    AssertEqual(c4err.domain, NetworkDomain);
    AssertEqual(c4err.code, kC4NetErrTLSHandshakeFailed);
    
    error = [NSError errorWithDomain: NSURLErrorDomain
                                code: kCFURLErrorCannotFindHost
                            userInfo: nil];
    convertError(error, &c4err);
    AssertEqual(c4err.domain, LiteCoreDomain);
    AssertEqual(c4err.code, kC4ErrorRemoteError);
}

- (void) testConvertErrorFleeceToNSError {
    NSError* error;
    AssertFalse(convertError(kFLEncodeError, &error));
    
    AssertEqual(error.code, kFLEncodeError);
    AssertEqualObjects(error.domain, @"CouchbaseLite.Fleece");
}

- (void)testConvertErrorFleeceToC4Error {
    C4Error c4Error;
    AssertFalse(convertError(kFLEncodeError, &c4Error));
    
    AssertEqual(c4Error.code, kFLEncodeError);
    AssertEqual(c4Error.domain, FleeceDomain);
}

@end
