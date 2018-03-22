//
//  ProxyTest.m
//  CBL ObjC Tests
//
//  Created by Jens Alfke on 3/21/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLHTTPLogic.h"

@interface ProxyTest : CBLTestCase

@end

@implementation ProxyTest

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}


- (NSDictionary*) proxySettings {
    return @{(id)kCFProxyTypeKey: (id)kCFProxyTypeHTTP,
             (id)kCFProxyHostNameKey: @"proxy.local",
             (id)kCFProxyPortNumberKey: @8080};
}

- (void)testHTTPRequestWithoutProxy {
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL: [NSURL URLWithString: @"http://www.example.com:9393/foo/bar?mode=vibrant#ref"]];
    CBLHTTPLogic* logic = [[CBLHTTPLogic alloc] initWithURLRequest: urlRequest];

    AssertFalse(logic.usingHTTPProxy);
    AssertEqualObjects(logic.directHost, @"www.example.com");
    AssertEqual(logic.directPort, 9393);

    NSString *request = [[NSString alloc] initWithData: logic.HTTPRequestData
                                              encoding: NSUTF8StringEncoding];
    Log(@"request:\n%@", request);
    Assert([request hasPrefix: @"GET /foo/bar?mode=vibrant HTTP/1.1\r\n"
                                "Host: www.example.com:9393\r\n"]);
}

- (void)testHTTPRequest {
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL: [NSURL URLWithString: @"http://www.example.com:9393/foo/bar?mode=vibrant#ref"]];
    CBLHTTPLogic* logic = [[CBLHTTPLogic alloc] initWithURLRequest: urlRequest];
    logic.proxySettings = self.proxySettings;

    Assert(logic.usingHTTPProxy);
    AssertEqualObjects(logic.directHost, @"proxy.local");
    AssertEqual(logic.directPort, 8080);

    NSString *request = [[NSString alloc] initWithData: logic.HTTPRequestData
                                              encoding: NSUTF8StringEncoding];
    Log(@"request:\n%@", request);
    Assert([request hasPrefix: @"GET http://www.example.com:9393/foo/bar?mode=vibrant HTTP/1.1\r\n"
                                "Host: www.example.com:9393\r\n"]);
}

- (void)testProxyCONNECT {
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL: [NSURL URLWithString: @"http://www.example.com:9393/foo/bar?mode=vibrant#ref"]];
    CBLHTTPLogic* logic = [[CBLHTTPLogic alloc] initWithURLRequest: urlRequest];
    logic.proxySettings = self.proxySettings;
    logic.useProxyCONNECT = YES;

    Assert(logic.usingHTTPProxy);
    AssertEqualObjects(logic.directHost, @"proxy.local");
    AssertEqual(logic.directPort, 8080);

    NSString *request = [[NSString alloc] initWithData: logic.HTTPRequestData
                                              encoding: NSUTF8StringEncoding];
    Log(@"CONNECT request:\n%@", request);
    Assert([request hasPrefix: @"CONNECT www.example.com:9393 HTTP/1.1\r\n"
            "Host: www.example.com:9393\r\n"]);
}

@end
