//
//  CBLRemoteRequest.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@protocol CBLAuthorizer, CBLRemoteRequestDelegate;
@class CBLCookieStorage, CBLRemoteSession;


UsingLogDomain(RemoteRequest);


/** The signature of the completion block called by a CBLRemoteRequest.
    @param result  On success, a 'result' object; by default this is the CBLRemoteRequest iself, but subclasses may return something else. On failure, this will likely be nil.
    @param error  The error, if any, else nil. */
typedef void (^CBLRemoteRequestCompletionBlock)(id result, NSError* error);


void CBLWarnUntrustedCert(NSString* host, SecTrustRef trust);


/** Asynchronous HTTP request; a fairly simple wrapper around NSURLConnection that calls a completion block when ready. */
@interface CBLRemoteRequest : NSObject
{
    @protected
    NSMutableURLRequest* _request;
    id<CBLAuthorizer> _authorizer;
    CBLCookieStorage* _cookieStorage;
    id<CBLRemoteRequestDelegate> _delegate;
    CBLRemoteRequestCompletionBlock _onCompletion;
    NSURLSessionTask* _task;
    int _status;
    NSDictionary* _responseHeaders;
    UInt8 _retryCount;
    bool _dontLog404;
    bool _challenged;
    bool _autoRetry;
}

/** Creates a request; call -start to send it on its way. */
- (instancetype) initWithMethod: (NSString*)method
                            URL: (NSURL*)url
                           body: (id)body
                   onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion;

@property NSTimeInterval timeoutInterval;
@property (strong, nonatomic) id<CBLAuthorizer> authorizer;
@property (strong, nonatomic) id<CBLRemoteRequestDelegate> delegate;
@property (strong, nonatomic) CBLCookieStorage* cookieStorage;
@property (nonatomic) bool autoRetry;   // Default value is YES
@property (nonatomic) bool dontStop;

/** Applies GZip compression to the request body if appropriate. */
- (BOOL) compressBody;

/** In some cases a kCBLStatusNotFound Not Found is an expected condition and shouldn't be logged; call this to suppress that log message. */
- (void) dontLog404;

/** Stops the request, calling the onCompletion block. */
- (void) stop;

@property (readonly) NSDictionary* responseHeaders;

/** JSON-compatible dictionary with status information, to be returned from _active_tasks API */
@property (readonly) NSMutableDictionary* statusInfo;

@property (readonly) BOOL running;

// protected:
- (void) clearConnection;
- (void) cancelWithStatus: (int)status message: (NSString*)message;
- (void) respondWithResult: (id)result error: (NSError*)error;
- (BOOL) retry;

// connection callbacks (protected)
- (NSInputStream *) needNewBodyStream;
- (void) didReceiveResponse:(NSHTTPURLResponse *)response;
- (void) didReceiveData:(NSData *)data;
- (void) didFinishLoading;
- (void) didFailWithError:(NSError *)error;

// called by CBLRemoteSession (protected)
@property (weak) CBLRemoteSession* session;
@property (readonly, atomic) NSURLSessionTask* task;
- (NSURLSessionTask*) createTaskInURLSession: (NSURLSession*)session;
- (NSURLCredential*) credentialForHTTPAuthChallenge: (NSURLAuthenticationChallenge*)challenge
                                disposition: (NSURLSessionAuthChallengeDisposition*)outDisposition;
- (NSURLCredential*) credentialForClientCertChallenge: (NSURLAuthenticationChallenge*)challenge
                                disposition: (NSURLSessionAuthChallengeDisposition*)outDisposition;
- (SecTrustRef) checkServerTrust:(NSURLAuthenticationChallenge*)challenge;
- (NSURLRequest*) willSendRequest:(NSURLRequest *)request
                 redirectResponse:(NSURLResponse *)response;

#if DEBUG
@property BOOL debugAlwaysTrust;    // For unit tests only!
#endif

@end


/** A request that parses its response body as JSON.
    The parsed object will be returned as the first parameter of the completion block. */
@interface CBLRemoteJSONRequest : CBLRemoteRequest
{
    @private
    NSMutableData* _jsonBuffer;
}
@end


@protocol CBLRemoteRequestDelegate <NSObject>

- (void) remoteRequestReceivedResponse: (CBLRemoteRequest*)request;
- (BOOL) checkSSLServerTrust: (NSURLProtectionSpace*)protectionSpace;

@end
