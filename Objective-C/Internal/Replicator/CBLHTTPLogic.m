//
//  CBLHTTPLogic.m
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

#import "CBLHTTPLogic.h"
#import "MYErrorUtils.h"
#import "MYURLUtils.h"


#define kMaxRedirects 10


@implementation CBLHTTPLogic
{
    NSMutableURLRequest* _urlRequest;
    NSDictionary* _proxySettings;
    CBLProxyType _proxyType;
    NSString* _nonceKey;
    CFHTTPMessageRef _responseMsg;
    NSString* _authorizationHeader, *_proxyAuthorizationHeader;
    NSURLCredential* _credential, *_proxyCredential;
    NSUInteger _redirectCount;
}


@synthesize handleRedirects=_handleRedirects, shouldContinue=_shouldContinue;
@synthesize shouldRetry=_shouldRetry, credential=_credential, httpStatus=_httpStatus, error=_error;
@synthesize proxySettings=_proxySettings, proxyType=_proxyType, useProxyCONNECT=_useProxyCONNECT;


static NSDictionary* sOverrideProxySettings;


- (instancetype) initWithURLRequest:(NSURLRequest *)urlRequest {
    NSParameterAssert(urlRequest);
    self = [super init];
    if (self) {
        _urlRequest = [urlRequest mutableCopy];
        _handleRedirects = YES;
        [self lookupProxySettings];
    }
    return self;
}


- (void) dealloc {
    if (_responseMsg) CFRelease(_responseMsg);
}


- (NSURL*) URL {
    return (NSURL*)_urlRequest.URL;
}


- (NSString*) directHost {
    if (_proxyType == kCBLNoProxy)
        return self.URL.host;
    else
        return _proxySettings[(id)kCFProxyHostNameKey];
}


- (UInt16) directPort {
    if (_proxyType == kCBLNoProxy)
        return self.port;
    NSNumber* portObj = _proxySettings[(id)kCFProxyPortNumberKey];
    if (portObj)
        return portObj.unsignedShortValue;
    else if ([_proxySettings[(id)kCFProxyTypeKey] isEqualToString: (id)kCFProxyTypeHTTPS])
        return 443;
    else
        return 80;
}


- (UInt16) port {
    return self.URL.my_effectivePort;
}


- (BOOL) useTLS {
    switch (_proxyType) {
        case kCBLNoProxy: {
            NSString* scheme = self.URL.scheme.lowercaseString;
            return [scheme isEqualToString: @"https"] || [scheme isEqualToString: @"wss"];
        }
        case kCBLHTTPProxy:
            return NO; // TODO: How about TLS Connection from client to proxy?
        case kCBLSOCKSProxy:
            return NO;
    }
}


+ (NSString*) userAgent {
    NSProcessInfo* process = [NSProcessInfo processInfo];
    NSString* appVers = (__bridge NSString*)CFBundleGetValueForInfoDictionaryKey(
                                                 CFBundleGetMainBundle(), kCFBundleVersionKey);
    return [NSString stringWithFormat: @"%@/%@ (%@ %@)",
                    process.processName, (appVers ?: @"0.0"),
#if TARGET_OS_IPHONE
                    @"iOS",
#else
                    @"Mac OS X",
#endif
                    process.operatingSystemVersionString];
}


- (void) setErrorCode: (NSInteger)code userInfo: (NSDictionary*)userInfo {
    NSMutableDictionary* info = [@{NSURLErrorFailingURLErrorKey: self.URL} mutableCopy];
    if (userInfo)
        [info addEntriesFromDictionary: userInfo];
    _error = [NSError errorWithDomain: NSURLErrorDomain code: code userInfo: info];
}


#pragma mark - REQUEST:


- (void) setValue: (NSString*)value forHTTPHeaderField:(NSString*)header {
    [_urlRequest setValue: value forHTTPHeaderField: header];
}

- (void) addValue: (NSString*)value forHTTPHeaderField:(NSString*)header {
    [_urlRequest addValue: value forHTTPHeaderField: header];
}

- (void) setObject: (NSString*)value forKeyedSubscript: (NSString*)key {
    [_urlRequest setValue: value forHTTPHeaderField: key];
}


- (CFHTTPMessageRef) newHTTPRequest {
    NSURL* url = self.URL;
    // Set/update the "Host" header:
    NSString* host = url.host;
    if (url.port)
        host = [host stringByAppendingFormat: @":%@", url.port];
    [self setValue: host forHTTPHeaderField: @"Host"];

    // Create the CFHTTPMessage:
    CFHTTPMessageRef httpMsg;
    if (_proxyType == kCBLHTTPProxy && _useProxyCONNECT) {
        NSURL *requestURL = [NSURL URLWithString: $sprintf(@"%@:%d", url.host, url.my_effectivePort)];
        httpMsg = CFHTTPMessageCreateRequest(NULL,
                                             CFSTR("CONNECT"),
                                             (__bridge CFURLRef)requestURL,
                                             kCFHTTPVersion1_1);
    } else {
        httpMsg = CFHTTPMessageCreateRequest(NULL,
                                             (__bridge CFStringRef)_urlRequest.HTTPMethod,
                                             (__bridge CFURLRef)url,
                                             kCFHTTPVersion1_1);
    }

    NSDictionary* headers = _urlRequest.allHTTPHeaderFields;
    for (NSString* header in headers)
        CFHTTPMessageSetHeaderFieldValue(httpMsg, (__bridge CFStringRef)header,
                                         (__bridge CFStringRef)headers[header]);

    // Add cookie headers from the NSHTTPCookieStorage:
    if (_urlRequest.HTTPShouldHandleCookies) {
        NSArray* cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL: url];
        NSDictionary* cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies: cookies];
        for (NSString* headerName in cookieHeaders) {
            CFHTTPMessageSetHeaderFieldValue(httpMsg,
                                             (__bridge CFStringRef)headerName,
                                             (__bridge CFStringRef)cookieHeaders[headerName]);
        }
    }

    // Add User-Agent if necessary:
    if (![_urlRequest valueForHTTPHeaderField: @"User-Agent"])
        CFHTTPMessageSetHeaderFieldValue(httpMsg, CFSTR("User-Agent"),
                                         (__bridge CFStringRef)[[self class] userAgent]);

    // Proactively add HTTP proxy auth if it's been explicitly configured:
    if (_proxyType == kCBLHTTPProxy) {
        NSString* username = _proxySettings[(id)kCFProxyUsernameKey];
        if (username) {
            NSString* password = _proxySettings[(id)kCFProxyPasswordKey] ?: @"";
            NSString* auth = $sprintf(@"%@:%@", username, password);
            auth = [[auth dataUsingEncoding: NSUTF8StringEncoding] base64EncodedStringWithOptions: 0];
            auth = $sprintf(@"Basic: %@", auth);
            CFHTTPMessageSetHeaderFieldValue(httpMsg,
                                             CFSTR("Proxy-Authorization"),
                                             (__bridge CFStringRef)auth);
        }
    }

    // Add authentication:
    if (_responseMsg && _credential.user && !(_proxyType == kCBLHTTPProxy && _useProxyCONNECT)) {
        if (![self addAuthentication: _credential toRequest: httpMsg forProxy: false])
            _credential = nil;
    }
    if (_responseMsg && _proxyCredential.user && _proxyType == kCBLHTTPProxy) {
        if (![self addAuthentication: _proxyCredential toRequest: httpMsg forProxy: true])
            _proxyCredential = nil;
    }
    _authorizationHeader = getHeader(httpMsg, @"Authorization");
    _proxyAuthorizationHeader = getHeader(httpMsg, @"Proxy-Authorization");

    NSData* body = _urlRequest.HTTPBody;
    if (body) {
        CFHTTPMessageSetHeaderFieldValue(httpMsg, CFSTR("Content-Length"),
                                         (__bridge CFStringRef)[@(body.length) description]);
        CFHTTPMessageSetBody(httpMsg, (__bridge CFDataRef)body);
    }

    _shouldContinue = _shouldRetry = NO;
    _httpStatus = 0;

    return httpMsg;
}


- (NSData*) HTTPRequestData {
    CFHTTPMessageRef rq = [self newHTTPRequest];
    NSData* data = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(rq));
    CFRelease(rq);

    if (_proxyType == kCBLHTTPProxy && !_useProxyCONNECT) {
        // CFHTTPMessage doesn't know how to create a proxy form of a request, where the request
        // line contains the entire URL. So splice in the scheme/host/port in front of the path:
        NSMutableData* mdata = [data mutableCopy];
        NSUInteger insertAt = _urlRequest.HTTPMethod.length + 1;    // before the "/"
        CFRange pathRange;
        NSData* urlData = self.URL.dataRepresentation;
        CFURLGetByteRangeForComponent((__bridge CFURLRef)self.URL, kCFURLComponentPath, &pathRange);
        NSData* schemeAndHost = [urlData subdataWithRange: NSMakeRange(0, pathRange.location)];
        [mdata replaceBytesInRange: NSMakeRange(insertAt, 0)
                         withBytes: schemeAndHost.bytes
                            length: schemeAndHost.length];
        data = mdata;
    }
    return data;
}


#pragma mark - RESPONSE HANDLING:


- (void) receivedResponse: (CFHTTPMessageRef)response {
    NSParameterAssert(response);
    if (response == _responseMsg)
        return;
    if (_responseMsg)
        CFRelease(_responseMsg);
    _responseMsg = response;
    CFRetain(_responseMsg);

    _shouldContinue = _shouldRetry = NO;
    _httpStatus = (int) CFHTTPMessageGetResponseStatusCode(_responseMsg);
    switch (_httpStatus) {
        case 301:
        case 302:
        case 305:
        case 307: {
            // Redirect:
            if (!_handleRedirects)
                break;
            if (++_redirectCount > kMaxRedirects) {
                [self setErrorCode: NSURLErrorHTTPTooManyRedirects userInfo: nil];
            } else if (![self redirect]) {
                [self setErrorCode: NSURLErrorRedirectToNonExistentLocation userInfo: nil];
            } else {
                _shouldRetry = YES;
            }
            break;
        }

        case 401: {
            NSString* authResponse = getHeader(_responseMsg, @"WWW-Authenticate");
            if (!_authorizationHeader) {
                if (!_credential)
                    _credential = [self credentialForAuthHeader: authResponse];
                CBLLog(WebSocket, @"%@: Auth challenge; credential = %@", self, _credential);
                if (_credential) {
                    // Recoverable auth failure -- try again with new _credential:
                    _shouldRetry = YES;
                    break;
                }
            }
            CBLLog(WebSocket, @"%@: HTTP auth failed; sent Authorization: %@  ;  got WWW-Authenticate: %@",
                self, _authorizationHeader, authResponse);
            NSDictionary* challengeInfo = [[self class] parseAuthHeader: authResponse];
            
            NSMutableDictionary* errorInfo = [NSMutableDictionary new];
            if (_authorizationHeader)
                errorInfo[@"HTTPAuthorization"] = _authorizationHeader;
            if (authResponse)
                errorInfo[@"HTTPAuthenticateHeader"] = authResponse;
            if (challengeInfo)
                errorInfo[@"AuthChallenge"] = challengeInfo;
            [self setErrorCode: NSURLErrorUserAuthenticationRequired userInfo: errorInfo];
            break;
        }

        case 407: {
            //TODO: Look up proxy credentials in Keychain and retry with those
            NSString* authResponse = getHeader(_responseMsg, @"Proxy-Authenticate");
            if (!_proxyAuthorizationHeader) {
                if (!_proxyCredential)
                    _proxyCredential = [self credentialForAuthHeader: authResponse];
                CBLLog(WebSocket, @"%@: Proxy auth challenge; credential = %@", self, _proxyCredential);
                if (_proxyCredential) {
                    // Recoverable auth failure -- try again with new _proxyCredential:
                    _shouldRetry = YES;
                    break;
                }
            }
            CBLLog(WebSocket, @"%@: HTTP proxy auth failed;  got Proxy-Authenticate: %@",
                   self, authResponse);
            [self setErrorCode: kCFErrorHTTPBadProxyCredentials userInfo: nil];
            break;
        }

        default:
            if (_httpStatus < 300)
                _shouldContinue = YES;
            break;
    }
}


- (NSString*) httpStatusMessage {
    NSString* line = CFBridgingRelease(CFHTTPMessageCopyResponseStatusLine(_responseMsg));
    NSRegularExpression* re = [NSRegularExpression
            regularExpressionWithPattern: @"^HTTP/\\d.\\d\\s+\\d+\\s+(.*)" options: 0 error: NULL];
    Assert(re);
    NSTextCheckingResult *match = [re firstMatchInString: line options: 0
                                                   range: NSMakeRange(0, line.length)];
    if (match.numberOfRanges >= 2)
        return [line substringWithRange: [match rangeAtIndex: 1]];
    else
        return line;
}


- (BOOL) redirect {
    NSString* location = getHeader(_responseMsg, @"Location");
    if (!location)
        return NO;
    NSURL* url = [NSURL URLWithString: location relativeToURL: self.URL];
    if (!url)
        return NO;
    if ([url.scheme caseInsensitiveCompare: @"http"] != 0 &&
            [url.scheme caseInsensitiveCompare: @"https"] != 0)
        return NO;
    if (_httpStatus == 305) {
        return _proxyType == kCBLNoProxy && [self setProxyURL: url];
    } else {
        _urlRequest.URL = url;
        [self lookupProxySettings];
    }
    return YES;
}


static NSString* getHeader(CFHTTPMessageRef message, NSString* header) {
    return CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(message,
                                                               (__bridge CFStringRef)header));
}


#pragma mark - AUTHENTICATION:


- (NSURLCredential*) credentialForAuthHeader: (NSString*)authHeader {
    // Basic & digest auth: http://www.ietf.org/rfc/rfc2617.txt
    NSDictionary* challenge = [[self class] parseAuthHeader: authHeader];
    if (!challenge)
        return nil;

    // Get the auth type:
    NSString* authenticationMethod;
    NSString* scheme = challenge[@"Scheme"];
    if ([scheme isEqualToString: @"Basic"])
        authenticationMethod = NSURLAuthenticationMethodHTTPBasic;
    else if ([scheme isEqualToString: @"Digest"])
        authenticationMethod = NSURLAuthenticationMethodHTTPDigest;
    else
        return nil;

    // Get the realm:
    NSString* realm = challenge[@"realm"];
    if (!realm)
        return nil;

    NSURLCredential* cred;
    cred = [self credentialForRealm: realm authenticationMethod: authenticationMethod];
    if (!cred.hasPassword)
        cred = nil;     // TODO: Add support for client certs
    return cred;
}


+ (NSDictionary*) parseAuthHeader: (NSString*)authHeader {
    if (!authHeader)
        return nil;
    NSMutableDictionary* challenge = [NSMutableDictionary new];
    NSRegularExpression* re = [NSRegularExpression
                            regularExpressionWithPattern: @"\(\\w+)\\s+(\\w+)=((\\w+)|\"([^\"]+))"
                            options: 0 error: NULL];
    NSAssert(re, @"Invalid regex");
    NSArray<NSTextCheckingResult*>* matches = [re matchesInString: authHeader options: 0
                                                            range: NSMakeRange(0, authHeader.length)];
    NSTextCheckingResult* groups = matches.firstObject;
    if (groups) {
        NSString* key = [authHeader substringWithRange: [groups rangeAtIndex: 2]];
        NSRange k = [groups rangeAtIndex: 4];
        if (k.length == 0)
            k = [groups rangeAtIndex: 5];
        challenge[key] = [authHeader substringWithRange: k];
        challenge[@"Scheme"] = [authHeader substringWithRange: [groups rangeAtIndex: 1]];
    }
    challenge[@"WWW-Authenticate"] = authHeader;
    return challenge;
}


- (bool) addAuthentication: (NSURLCredential*)credential
                 toRequest: (CFHTTPMessageRef)httpMsg
                  forProxy: (bool)forProxy
{
    NSString* password = credential.password;
    if (!password ||
        (!CFHTTPMessageAddAuthentication(httpMsg, _responseMsg,
                                         (__bridge CFStringRef)credential.user,
                                         (__bridge CFStringRef)password,
                                         NULL,
                                         forProxy)
         && !CFHTTPMessageAddAuthentication(httpMsg, _responseMsg,
                                            (__bridge CFStringRef)credential.user,
                                            (__bridge CFStringRef)password,
                                            kCFHTTPAuthenticationSchemeBasic, // fallback
                                            forProxy)))
    {
        // The 2nd call above works around a bug where it can fail if the auth scheme is NULL.
        CBLWarn(WebSocket, @"%@: Unable to add HTTP authentication", self);
        CFRelease(_responseMsg);
        _responseMsg = NULL;
        return false;
    }

    return true;
}


// Adapted from MYURLUtils.m
- (NSURLProtectionSpace*) protectionSpaceWithRealm: (NSString*)realm
                                 authenticationMethod: (NSString*)authenticationMethod
{
    NSString* protocol = self.useTLS ? NSURLProtectionSpaceHTTPS
                                     : NSURLProtectionSpaceHTTP;
    return [[NSURLProtectionSpace alloc] initWithHost: (NSString*)self.URL.host
                                                 port: self.port
                                             protocol: protocol
                                                realm: realm
                                 authenticationMethod: authenticationMethod];
}


// Adapted from MYURLUtils.m
- (NSURLCredential*) credentialForRealm: (NSString*)realm
                      authenticationMethod: (NSString*)authenticationMethod
{
    if ([authenticationMethod isEqualToString: NSURLAuthenticationMethodServerTrust])
        return nil;
    NSURL* url = self.URL;
    NSString* username = url.user;
    NSString* password = url.password;
    if (username && password)
        return [NSURLCredential credentialWithUser: username password: password
                                       persistence: NSURLCredentialPersistenceNone];

    NSURLProtectionSpace* space = [self protectionSpaceWithRealm: realm
                                            authenticationMethod: authenticationMethod];
    NSURLCredentialStorage* storage = [NSURLCredentialStorage sharedCredentialStorage];
    if (username)
        return [[storage credentialsForProtectionSpace: space] objectForKey: username];
    else
        return [storage defaultCredentialForProtectionSpace: space];
}


#pragma mark - PROXY SUPPORT:


+ (void) setOverrideProxySettings: (NSDictionary*)proxySettings {
    sOverrideProxySettings = [proxySettings copy];
}


- (void) lookupProxySettings {
    self.proxySettings = sOverrideProxySettings ?: _urlRequest.URL.my_proxySettings;
}


- (void) setProxySettings: (NSDictionary*)settings {
    _error = nil;       // Might get set if PAC resolution fails
    NSString* type = settings[(id)kCFProxyTypeKey];
    if ([type isEqualToString: (id)kCFProxyTypeAutoConfigurationURL])
        settings = [self resolveProxyAutoConfig: settings isURL: YES];
    else if ([type isEqualToString: (id)kCFProxyTypeAutoConfigurationJavaScript])
        settings = [self resolveProxyAutoConfig: settings isURL: NO];

    type = settings[(id)kCFProxyTypeKey];
    if ([type isEqualToString: (id)kCFProxyTypeHTTP]
                || [type isEqualToString: (id)kCFProxyTypeHTTPS])
        _proxyType = kCBLHTTPProxy;
    else if ([type isEqualToString: (id)kCFProxyTypeSOCKS])
        _proxyType = kCBLSOCKSProxy;
    else {
        _proxyType = kCBLNoProxy;
    }
    _proxySettings = [settings copy];
}


- (BOOL) setProxyURL: (NSURL*)proxyURL {
    NSString* host = proxyURL.host;
    if ([proxyURL.scheme.lowercaseString hasPrefix: @"http"] && host) {
        id type = proxyURL.my_isHTTPS ? (id)kCFProxyTypeHTTPS : (id)kCFProxyTypeHTTP;
        self.proxySettings = @{(id)kCFProxyTypeKey:       type,
                               (id)kCFProxyHostNameKey:   host,
                               (id)kCFProxyPortNumberKey: @(proxyURL.my_effectivePort)};
        return true;
    } else {
        self.proxySettings = nil;
        return (proxyURL == nil);
    }
}


#define kPrivatePACRunloopMode CFSTR("CBLPACResolution")


static void pacCallback(void *client, CFArrayRef proxyList, CFErrorRef error) {
    CFTypeRef* resultPtr = client;
    *resultPtr = proxyList ? CFRetain(proxyList) : CFRetain(error);
    CFRunLoopStop(CFRunLoopGetCurrent());
}


- (NSDictionary*) resolveProxyAutoConfig: (NSDictionary*)settings isURL: (BOOL)isURL {
    CFArrayRef proxies = NULL;
    CFErrorRef error = NULL;
    NSURL* pacURL;
    if (isURL) {
        pacURL = settings[(id)kCFProxyAutoConfigurationURLKey];
        // Request resolution of the PAC URL:
        CFTypeRef result = NULL;
        CFStreamClientContext ctx = {.info = &result};
        CFRunLoopSourceRef src = CFNetworkExecuteProxyAutoConfigurationURL(
                                    (__bridge CFURLRef)pacURL, (__bridge CFURLRef)self.URL,
                                    pacCallback, &ctx);
        // Wait for the result to arrive:
        CBLLogVerbose(WebSocket, @"%@: Resolving proxy PAC script at <%@> ...", self, pacURL);
        CFRunLoopRef rl = CFRunLoopGetCurrent();
        CFRunLoopAddSource(rl, src, kPrivatePACRunloopMode);
        CFRunLoopRunInMode(kPrivatePACRunloopMode, DBL_MAX, false);
        CFRunLoopRemoveSource(rl, src, kPrivatePACRunloopMode);

        if (CFGetTypeID(result) == CFErrorGetTypeID())
            error = (CFErrorRef)result;
        else
            proxies = result;
    } else {
        CBLLogVerbose(WebSocket, @"%@: Resolving proxy PAC script ...", self);
        NSString* js = settings[(id)kCFProxyAutoConfigurationJavaScriptKey];
        Assert(js);
        proxies = CFNetworkCopyProxiesForAutoConfigurationScript(
                                    (__bridge CFStringRef)js, (__bridge CFURLRef)self.URL, &error);
    }

    if (!proxies) {
        NSString* msg = [CFBridgingRelease(error) my_compactDescription];
        CBLWarn(WebSocket, @"Failed to resolve proxy PAC script at <%@>: %@", pacURL, msg);
        _error = MYError(kCFErrorPACFileError, (id)kCFErrorDomainCFNetwork,
                         @"Error resolving proxy autoconnect (PAC): %@", msg);
        return settings;
    }

    settings = [CFBridgingRelease(proxies) firstObject];
    CBLLogVerbose(WebSocket, @"%@: ... PAC resolved to %@", self, settings);
    return settings;
}

@end
