//
//  CBLHTTPLogic.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/** Implements the core logic of HTTP request/response handling, especially processing
    redirects and authentication challenges, without actually doing any of the networking.
    It just tells you what HTTP request to send and how to interpret the response. */
@interface CBLHTTPLogic : NSObject

- (instancetype) initWithURLRequest: (NSURLRequest *)request;

- (void) setValue: (nullable NSString*)value forHTTPHeaderField:(NSString*)header;
- (void) setObject: (nullable NSString*)value forKeyedSubscript: (NSString*)key;

/** Can be used to add multiple instances of a header. */
- (void) addValue: (nullable NSString*)value forHTTPHeaderField:(NSString*)header;

/** Set this to YES to handle redirects.
    If enabled, redirects are handled by updating the URL and setting shouldRetry. */
@property (nonatomic) BOOL handleRedirects;

@property (nonatomic, nullable) NSDictionary* proxySettings;

@property (nonatomic) BOOL useProxyCONNECT;

//@property (readonly, nonatomic) NSURLRequest* URLRequest;

/** Returns an encoded HTTP request. */
- (NSData*) HTTPRequestData;

/** Call this when a response is received, then check shouldContinue and shouldRetry. */
- (void) receivedResponse: (CFHTTPMessageRef)response;

/** After a response is received, this will be YES if the HTTP status indicates success. */
@property (readonly, nonatomic) BOOL shouldContinue;

/** After a response is received, this will be YES if the client needs to retry with a new
    request. If so, it should call -createHTTPRequest again to get the new request, which will
    have either a different URL or new authentication headers. */
@property (readonly, nonatomic) BOOL shouldRetry;

/** The URL. This will change after receiving a redirect response. */
@property (readonly, nonatomic) NSURL* URL;

/** The TCP port number, based on the URL. */
@property (readonly, nonatomic) UInt16 port;

/** Yes if TLS/SSL should be used (based on the URL). */
@property (readonly, nonatomic) BOOL useTLS;

/** YES if the connection must be made to an HTTP proxy. */
@property (readonly, nonatomic) BOOL usingHTTPProxy;

/** The direct hostname to open a socket to -- this will be the proxy's, if a proxy is used. */
@property (readonly, nonatomic) NSString* directHost;

/** The direct port number to open a socket to -- this will be the proxy's, if a proxy is used. */
@property (readonly, nonatomic) UInt16 directPort;

/** The auth credential being used. */
@property (readwrite, nullable, nonatomic) NSURLCredential* credential;

/** A default User-Agent header string that will be used if the URLRequest doesn't contain one.
    You can use this as the basis for your own by appending to it. */
+ (NSString*) userAgent;

/** The HTTP status code of the response. */
@property (readonly, nonatomic) int httpStatus;

/** The HTTP status message ("OK", "Not Found", ...) of the response. */
@property (readonly, nonatomic) NSString* httpStatusMessage;

/** The error from a failed redirect or authentication. This isn't set for regular non-success
    HTTP statuses like 404, only for failures to redirect or authenticate. */
@property (readonly, nullable, nonatomic) NSError* error;

/** Parses the value of a "WWW-Authenticate" header into a dictionary. In the dictionary, the key
    "WWW-Authenticate" will contain the entire header, "Scheme" will contain the scheme (the first
    word), and the first parameter and value will appear as an extra key/value. (Only the first
    parameter is parsed; this could be improved.) */
+ (nullable NSDictionary*) parseAuthHeader: (NSString*)authHeader;

#if DEBUG
// Exposed for testing. Registers proxy settings to use regardless of OS settings.
+ (void) setOverrideProxySettings: (nullable NSDictionary*)proxySettings;
#endif

@end


NS_ASSUME_NONNULL_END
