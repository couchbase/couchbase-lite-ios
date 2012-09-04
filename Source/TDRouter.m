//
//  TDRouter.m
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDRouter.h"
#import "TDDatabase+Insertion.h"
#import "TDServer.h"
#import "TDView.h"
#import "TDBody.h"
#import "TDMultipartWriter.h"
#import "TDReplicatorManager.h"
#import "TDInternal.h"
#import "ExceptionUtils.h"
#import "MYRegexUtils.h"

#ifdef GNUSTEP
#import <GNUstepBase/NSURL+GNUstepBase.h>
#else
#import <objc/message.h>
#endif


#ifdef GNUSTEP
static double TouchDBVersionNumber = 0.7;
#else
extern double TouchDBVersionNumber; // Defined in Xcode-generated TouchDB_vers.c
#endif


@interface TDRouter (Handlers)
- (TDStatus) do_GETRoot;
@end


@implementation TDRouter


+ (NSString*) versionString {
    return $sprintf(@"%g", TouchDBVersionNumber);
}


- (id) initWithDatabaseManager: (TDDatabaseManager*)dbManager request: (NSURLRequest*)request {
    NSParameterAssert(request);
    self = [super init];
    if (self) {
        _dbManager = [dbManager retain];
        _request = [request retain];
        _response = [[TDResponse alloc] init];
        _local = YES;
        _processRanges = YES;
        if (0) { // assignments just to appease static analyzer so it knows these ivars are used
            _longpoll = _changesIncludeDocs = _changesIncludeConflicts = NO;
        }
    }
    return self;
}

- (id) initWithServer: (TDServer*)server
              request: (NSURLRequest*)request
              isLocal: (BOOL)isLocal
{
    NSParameterAssert(server);
    NSParameterAssert(request);
    self = [self initWithDatabaseManager: nil request: request];
    if (self) {
        _server = [server retain];
        _local = isLocal;
        _processRanges = YES;
    }
    return self;
}

- (void)dealloc {
    [self stopNow];
    [_dbManager release];
    [_server release];
    [_request release];
    [_response release];
    [_queries release];
    [_path release];
    [_db release];
    [_changesFilter release];
    [_changesFilterParams release];
    [_onAccessCheck release];
    [_onResponseReady release];
    [_onDataAvailable release];
    [_onFinished release];
    [super dealloc];
}


@synthesize onAccessCheck=_onAccessCheck, onResponseReady=_onResponseReady,
            onDataAvailable=_onDataAvailable, onFinished=_onFinished,
            request=_request, response=_response, processRanges=_processRanges;


- (NSDictionary*) queries {
    if (!_queries) {
        NSString* queryString = _request.URL.query;
        if (queryString.length > 0) {
            NSMutableDictionary* queries = $mdict();
            for (NSString* component in [queryString componentsSeparatedByString: @"&"]) {
                NSRange equals = [component rangeOfString: @"="];
                if (equals.length == 0)
                    equals.location = component.length;
                NSString* key = [component substringToIndex: equals.location];
                NSString* value = [component substringFromIndex: NSMaxRange(equals)];
                queries[key] = value;
            }
            _queries = [queries copy];
        }
    }
    return _queries;
}


- (NSString*) query: (NSString*)param {
    return [(self.queries)[param]
                    stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
}

- (BOOL) boolQuery: (NSString*)param {
    NSString* value = [self query: param];
    return value && !$equal(value, @"false") && !$equal(value, @"0");
}

- (int) intQuery: (NSString*)param defaultValue: (int)defaultValue {
    NSString* value = [self query: param];
    return value ? value.intValue : defaultValue;
}

- (id) jsonQuery: (NSString*)param error: (NSError**)outError {
    if (outError)
        *outError = nil;
    NSString* value = [self query: param];
    if (!value)
        return nil;
    id result = [TDJSON JSONObjectWithData: [value dataUsingEncoding: NSUTF8StringEncoding]
                                   options: TDJSONReadingAllowFragments
                                     error: outError];
    if (!result)
        Warn(@"TDRouter: invalid JSON in query param ?%@=%@", param, value);
    return result;
}

- (NSMutableDictionary*) jsonQueries {
    NSMutableDictionary* queries = $mdict();
    [self.queries enumerateKeysAndObjectsUsingBlock: ^(NSString* param, NSString* value, BOOL *stop) {
        id parsed = [TDJSON JSONObjectWithData: [value dataUsingEncoding: NSUTF8StringEncoding]
                                       options: TDJSONReadingAllowFragments
                                         error: nil];
        if (parsed)
            queries[param] = parsed;
    }];
    return queries;
}


- (BOOL) cacheWithEtag: (NSString*)etag {
    NSString* eTag = $sprintf(@"\"%@\"", etag);
    _response[@"Etag"] = eTag;
    return $equal(eTag, [_request valueForHTTPHeaderField: @"If-None-Match"]);
}


- (NSDictionary*) bodyAsDictionary {
    return $castIf(NSDictionary, [TDJSON JSONObjectWithData: _request.HTTPBody
                                                    options: 0 error: NULL]);
}


- (TDContentOptions) contentOptions {
    TDContentOptions options = 0;
    if ([self boolQuery: @"attachments"])
        options |= kTDIncludeAttachments;
    if ([self boolQuery: @"local_seq"])
        options |= kTDIncludeLocalSeq;
    if ([self boolQuery: @"conflicts"])
        options |= kTDIncludeConflicts;
    if ([self boolQuery: @"revs"])
        options |= kTDIncludeRevs;
    if ([self boolQuery: @"revs_info"])
        options |= kTDIncludeRevsInfo;
    return options;
}


- (BOOL) getQueryOptions: (TDQueryOptions*)options {
    // http://wiki.apache.org/couchdb/HTTP_view_API#Querying_Options
    *options = kDefaultTDQueryOptions;
    options->skip = [self intQuery: @"skip" defaultValue: options->skip];
    options->limit = [self intQuery: @"limit" defaultValue: options->limit];
    options->groupLevel = [self intQuery: @"group_level" defaultValue: options->groupLevel];
    options->descending = [self boolQuery: @"descending"];
    options->includeDocs = [self boolQuery: @"include_docs"];
    options->includeDeletedDocs = [self boolQuery: @"include_deleted"];
    options->updateSeq = [self boolQuery: @"update_seq"];
    if ([self query: @"inclusive_end"])
        options->inclusiveEnd = [self boolQuery: @"inclusive_end"];
    options->reduce = [self boolQuery: @"reduce"];
    options->group = [self boolQuery: @"group"];
    options->content = [self contentOptions];
    NSError* error = nil;
    options->startKey = [self jsonQuery: @"startkey" error: &error];
    if (error)
        return NO;
    options->endKey = [self jsonQuery: @"endkey" error: &error];
    if (error)
        return NO;
    id key = [self jsonQuery: @"key" error: &error];
    if (error)
        return NO;
    if (key)
        options->keys = @[key];
    return YES;
}


- (NSString*) multipartRequestType {
    NSString* accept = [_request valueForHTTPHeaderField: @"Accept"];
    if ([accept hasPrefix: @"multipart/"])
        return accept;
    return nil;
}


- (NSString*) ifMatch {
    NSString* ifMatch = [_request valueForHTTPHeaderField: @"If-Match"];
    if (!ifMatch)
        return nil;
    // Value of If-Match is an ETag, so have to trim the quotes around it:
    if (ifMatch.length > 2 && [ifMatch hasPrefix: @"\""] && [ifMatch hasSuffix: @"\""])
        return [ifMatch substringWithRange: NSMakeRange(1, ifMatch.length-2)];
    else
        return nil;
}


- (TDStatus) openDB {
    // As a special case, the _replicator db is created on demand (as though it already existed)
    if (!_db.exists && !$equal(_db.name, kTDReplicatorDatabaseName))
        return kTDStatusNotFound;
    if (![_db open])
        return kTDStatusDBError;
    return kTDStatusOK;
}


static NSArray* splitPath( NSURL* url ) {
    // Unfortunately can't just call url.path because that converts %2F to a '/'.
#ifdef GNUSTEP
    NSString* pathString = [url pathWithEscapes];
#else
    NSString* pathString = NSMakeCollectable(CFURLCopyPath((CFURLRef)url));
#endif
    NSMutableArray* path = $marray();
    for (NSString* comp in [pathString componentsSeparatedByString: @"/"]) {
        if ([comp length] > 0) {
            NSString* unescaped = [comp stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            if (!unescaped) {
                path = nil;     // bad URL
                break;
            }
            [path addObject: unescaped];
        }
    }
#ifndef GNUSTEP
    [pathString release];
#endif
    return path;
}


- (TDStatus) route {
    // Refer to: http://wiki.apache.org/couchdb/Complete_HTTP_API_Reference
    
    // We're going to map the request into a selector based on the method and path.
    // Accumulate the selector into the string 'message':
    NSString* method = _request.HTTPMethod;
    if ($equal(method, @"HEAD"))
        method = @"GET";
    NSMutableString* message = [NSMutableString stringWithFormat: @"do_%@", method];
    
    // First interpret the components of the request:
    _path = [splitPath(_request.URL) mutableCopy];
    if (!_path)
        return kTDStatusBadRequest;
        
    NSUInteger pathLen = _path.count;
    if (pathLen > 0) {
        NSString* dbName = _path[0];
        BOOL validName = [TDDatabaseManager isValidDatabaseName: dbName];
        if ([dbName hasPrefix: @"_"] && !validName) {
            [message appendString: dbName]; // special root path, like /_all_dbs
        } else if (!validName) {
            return kTDStatusBadID;
        } else {
            _db = [[_dbManager databaseNamed: dbName] retain];
            if (!_db)
                return kTDStatusNotFound;
            [message appendString: @":"];
        }
    } else {
        [message appendString: @"Root"];
    }
    
    NSString* docID = nil;
    if (_db && pathLen > 1) {
        // Make sure database exists, then interpret doc name:
        TDStatus status = [self openDB];
        if (TDStatusIsError(status))
            return status;
        NSString* name = _path[1];
        if (![name hasPrefix: @"_"]) {
            // Regular document
            if (![TDDatabase isValidDocumentID: name])
                return kTDStatusBadID;
            docID = name;
        } else if ([name isEqualToString: @"_design"] || [name isEqualToString: @"_local"]) {
            // "_design/____" and "_local/____" are document names
            if (pathLen <= 2)
                return kTDStatusNotFound;
            docID = [name stringByAppendingPathComponent: _path[2]];
            _path[1] = docID;
            [_path removeObjectAtIndex: 2];
            --pathLen;
        } else if ([name hasPrefix: @"_design/"] || [name hasPrefix: @"_local/"]) {
            // This is also a document, just with a URL-encoded "/"
            docID = name;
        } else {
            // Special document name like "_all_docs":
            [message insertString: name atIndex: message.length-1]; // add to 1st component of msg
            if (pathLen > 2)
                docID = [[_path subarrayWithRange: NSMakeRange(2, _path.count-2)]
                         componentsJoinedByString: @"/"];
        }

        if (docID)
            [message appendString: @"docID:"];
    }
    
    NSString* attachmentName = nil;
    if (docID && pathLen > 2) {
        // Interpret attachment name:
        attachmentName = _path[2];
        if ([attachmentName hasPrefix: @"_"] && [docID hasPrefix: @"_design/"]) {
            // Design-doc attribute like _info or _view
            [message replaceOccurrencesOfString: @":docID:" withString: @":designDocID:"
                                        options:0 range: NSMakeRange(0, message.length)];
            docID = [docID substringFromIndex: 8];  // strip the "_design/" prefix
            [message appendString: [attachmentName substringFromIndex: 1]];
            [message appendString: @":"];
            attachmentName = pathLen > 3 ? _path[3] : nil;
        } else {
            [message appendString: @"attachment:"];
            if (pathLen > 3)
                attachmentName = [[_path subarrayWithRange: NSMakeRange(2, _path.count-2)]
                                                                componentsJoinedByString: @"/"];
        }
    }
    
    // Send myself a message based on the components:
    SEL sel = NSSelectorFromString(message);
    if (!sel || ![self respondsToSelector: sel]) {
        Log(@"TDRouter: unknown request type: %@ %@ (mapped to %@)",
             _request.HTTPMethod, _request.URL.path, message);
        Assert([self respondsToSelector: @selector(do_GETRoot)],
               @"TDRouter(Handlers) is missing -- app may be linked without -ObjC linker flag.");
        sel = @selector(do_UNKNOWN);
    }
    
    if (_onAccessCheck) {
        TDStatus status = _onAccessCheck(_db, docID, sel);
        if (TDStatusIsError(status)) {
            LogTo(TDRouter, @"Access check failed for %@", _db.name);
            return status;
        }
    }
    
#ifdef GNUSTEP
    IMP fn = objc_msg_lookup(self, sel);
    return (TDStatus) fn(self, sel, _db, docID, attachmentName);
#else
    return (TDStatus) objc_msgSend(self, sel, _db, docID, attachmentName);
#endif
}


- (void) run {
    if (WillLogTo(TDRouter)) {
        NSMutableString* output = [NSMutableString stringWithFormat: @"%@ %@",
                                   _request.HTTPMethod, _request.URL];
        if (_request.HTTPBodyStream)
            [output appendString: @" + body stream"];
        else if (_request.HTTPBody.length > 0)
            [output appendFormat: @" + %llu-byte body", (uint64_t)_request.HTTPBody.length];
        NSDictionary* headers = _request.allHTTPHeaderFields;
        for (NSString* key in headers)
            [output appendFormat: @"\n\t%@: %@", key, headers[key]];
        LogTo(TDRouter, @"%@", output);
    }
    
    Assert(_dbManager);
    // Call the appropriate handler method:
    TDStatus status;
    @try {
        status = [self route];
    } @catch (NSException *x) {
        MYReportException(x, @"handling TouchDB request");
        status = kTDStatusException;
        [_response reset];
    }
    
    // If response is ready (nonzero status), tell my client about it:
    if (status > 0) {
        _response.internalStatus = status;
        [self processRequestRanges];
        [self sendResponseHeaders];
        [self sendResponseBodyAndFinish: !_waiting];
    } else {
        _waiting = YES;
    }
    
    // If I will keep running asynchronously (i.e. a _changes feed handler), listen for the
    // database closing so I can stop then:
    if (_waiting)
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbClosing:)
                                                     name: TDDatabaseWillCloseNotification
                                                   object: _db];
}


- (void) processRequestRanges {
    if (!_processRanges || _response.status != 200 || !($equal(_request.HTTPMethod, @"GET") ||
                                                        $equal(_request.HTTPMethod, @"HEAD"))) {
        return;
    }

    _response[@"Accept-Ranges"] = @"bytes";

    NSData* body = _response.body.asJSON;  // misnomer; may not be JSON
    NSUInteger bodyLength = body.length;
    if (bodyLength == 0)
        return;

    // Range requests: http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.35
    NSString* rangeHeader = [_request valueForHTTPHeaderField: @"Range"];
    if (!rangeHeader)
        return;

    // Parse the header value into 'from' and 'to' range strings:
    static NSRegularExpression* regex;
    if (!regex)
        regex = [$regex(@"^bytes=(\\d+)?-(\\d+)?$") retain];
    NSTextCheckingResult *match = [regex firstMatchInString: rangeHeader options: 0
                                                      range: NSMakeRange(0, rangeHeader.length)];
    if (!match) {
        Warn(@"Invalid request Range header value: '%@'", rangeHeader);
        return;
    }
    NSString *fromStr=nil, *toStr = nil;
    NSRange r = [match rangeAtIndex: 1];
    if (r.length)
        fromStr = [rangeHeader substringWithRange: r];
    r = [match rangeAtIndex: 2];
    if (r.length)
        toStr = [rangeHeader substringWithRange: r];

    // Now convert those into the integer offsets (remember that 'to' is inclusive):
    NSUInteger from, to;
    if (fromStr.length > 0) {
        from = (NSUInteger)fromStr.integerValue;
        if (toStr.length > 0)
            to = MIN((NSUInteger)toStr.integerValue, bodyLength - 1);
        else
            to = bodyLength - 1;
        if (to < from)
            return;  // invalid range
    } else if (toStr.length > 0) {
        to = bodyLength - 1;
        from = bodyLength - MIN((NSUInteger)toStr.integerValue, bodyLength);
    } else {
        return;  // "-" is an invalid range
    }

    if (from >= bodyLength || to < from) {
        _response.status = 416; // Requested Range Not Satisfiable
        NSString* contentRangeStr = $sprintf(@"bytes */%llu", (uint64_t)bodyLength);
        _response[@"Content-Range"] = contentRangeStr;
        _response.body = nil;
        return;
    }

    body = [body subdataWithRange: NSMakeRange(from, to - from + 1)];
    _response.body = [TDBody bodyWithJSON: body];  // not actually JSON

    // Content-Range: http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.16
    NSString* contentRangeStr = $sprintf(@"bytes %llu-%llu/%llu",
                                         (uint64_t)from, (uint64_t)to, (uint64_t)bodyLength);
    _response[@"Content-Range"] = contentRangeStr;
    _response.status = 206; // Partial Content
    LogTo(TDRouter, @"Content-Range: %@", contentRangeStr);
}


- (void) sendResponseHeaders {
    if (_responseSent)
        return;
    _responseSent = YES;

    _response[@"Server"] = $sprintf(@"TouchDB %g", TouchDBVersionNumber);

    // Check for a mismatch between the Accept request header and the response type:
    NSString* accept = [_request valueForHTTPHeaderField: @"Accept"];
    if (accept && [accept rangeOfString: @"*/*"].length == 0) {
        NSString* responseType = _response.baseContentType;
        if (responseType && [accept rangeOfString: responseType].length == 0) {
            LogTo(TDRouter, @"Error kTDStatusNotAcceptable: Can't satisfy request Accept: %@", accept);
            _response.internalStatus = kTDStatusNotAcceptable;
            [_response reset];
        }
    }

    if (_response.body.isValidJSON)
        _response[@"Content-Type"] = @"application/json";

    if (_response.status == 200 && ($equal(_request.HTTPMethod, @"GET") ||
                                    $equal(_request.HTTPMethod, @"HEAD"))) {
        if (!_response[@"Cache-Control"])
            _response[@"Cache-Control"] = @"must-revalidate";
    }

    if (_onResponseReady)
        _onResponseReady(_response);
}


- (void) sendResponseBodyAndFinish: (BOOL)finished {
    if (_onDataAvailable && _response.body && !$equal(_request.HTTPMethod, @"HEAD")) {
        _onDataAvailable(_response.body.asJSON, finished);
    }
    if (finished)
        [self finished];
}


- (void) finished {
    if (WillLogTo(TDRouter)) {
        NSMutableString* output = [NSMutableString stringWithFormat: @"Response -- status=%d, body=%llu bytes",
                                   _response.status, (uint64_t)_response.body.asJSON.length];
        NSDictionary* headers = _response.headers;
        for (NSString* key in headers)
            [output appendFormat: @"\n\t%@: %@", key, headers[key]];
        LogTo(TDRouter, @"%@", output);
    }
    OnFinishedBlock onFinished = [_onFinished retain];
    [self stopNow];
    if (onFinished)
        onFinished();
    [onFinished release];
}


- (void) stopNow {
    _running = NO;
    self.onResponseReady = nil;
    self.onDataAvailable = nil;
    self.onFinished = nil;
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (void) stop {
    if (!_running)
        return;
    _running = NO;
    [_server queue: ^{ [self stopNow];  }];
}


- (void) start {
    _running = YES;
    if (_dbManager) {
        [self run];
    } else {
        [_server tellDatabaseManager: ^(TDDatabaseManager* dbm) {
            _dbManager = [dbm retain];
            [self run];
        }];
    }
}


- (TDStatus) do_UNKNOWN {
    return kTDStatusBadRequest;
}


- (void) dbClosing: (NSNotification*)n {
    LogTo(TDRouter, @"Database closing! Returning error 500");
    if (!_responseSent) {
        _response.internalStatus = 500;
        [self sendResponseHeaders];
    }
    [self finished];
}


@end


#pragma mark - TDRESPONSE

@implementation TDResponse

- (id) init
{
    self = [super init];
    if (self) {
        _status = kTDStatusOK;
        _headers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_statusMsg release];
    [_statusReason release];
    [_headers release];
    [_body release];
    [super dealloc];
}

- (void) reset {
    [_headers removeAllObjects];
    setObj(&_body, nil);
}

@synthesize status=_status, internalStatus=_internalStatus, statusMsg=_statusMsg,
            statusReason=_statusReason, headers=_headers, body=_body;

- (void) setInternalStatus:(TDStatus)internalStatus {
    _internalStatus = internalStatus;
    NSString* statusMsg;
    self.status = TDStatusToHTTPStatus(internalStatus, &statusMsg);
    setObjCopy(&_statusMsg, statusMsg);
    if (_status < 300) {
        if (!_body && !_headers[@"Content-Type"]) {
            self.body = [TDBody bodyWithJSON:
                                    [@"{\"ok\":true}" dataUsingEncoding: NSUTF8StringEncoding]];
        }
    } else {
        self.bodyObject = $dict({@"status", @(_status)},
                                {@"error", statusMsg},
                                {@"reason", _statusReason});
        self[@"Content-Type"]= @"application/json";
    }
}

- (NSString*) objectForKeyedSubscript: (NSString*)header {
    return _headers[header];
}

- (void)setObject: (NSString*)value forKeyedSubscript:(NSString*)header {
    [_headers setValue: value forKey: header];
}

- (NSString*) baseContentType {
    NSString* type = _headers[@"Content-Type"];
    if (!type)
        return nil;
    NSRange r = [type rangeOfString: @";"];
    if (r.length > 0)
        type = [type substringToIndex: r.location];
    return type;
}

- (id) bodyObject {
    return self.body.asObject;
}

- (void) setBodyObject:(id)bodyObject {
    self.body = bodyObject ? [TDBody bodyWithProperties: bodyObject] : nil;
}

- (void) setMultipartBody: (TDMultipartWriter*)mp {
    // OPT: Would be better to stream this than shoving all the data into _body.
    self.body = [TDBody bodyWithJSON: mp.allOutput];
    self[@"Content-Type"] = mp.contentType;
}

- (void) setMultipartBody: (NSArray*)parts type: (NSString*)type {
    TDMultipartWriter* mp = [[TDMultipartWriter alloc] initWithContentType: type
                                                                      boundary: nil];
    for (id part in parts) {
        if (![part isKindOfClass: [NSData class]]) {
            part = [TDJSON dataWithJSONObject: part options: 0 error: NULL];
            [mp setNextPartsHeaders: $dict({@"Content-Type", @"application/json"})];
        }
        [mp addData: part];
    }
    [self setMultipartBody: mp];
    [mp release];
}

@end
