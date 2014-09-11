//
//  CBL_Router.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Router.h"
#import "CBLDatabase+Insertion.h"
#import "CBL_Server.h"
#import "CBLView+Internal.h"
#import "CBL_Body.h"
#import "CBLMultipartWriter.h"
#import "CBLJSON.h"
#import "CBLMisc.h"
#import "CBLGeometry.h"

#import "ExceptionUtils.h"
#import "CollectionUtils.h"
#import "Test.h"
#import "MYRegexUtils.h"
#import "MYURLUtils.h"

#ifdef GNUSTEP
#import <GNUstepBase/NSURL+GNUstepBase.h>
#else
#import <objc/message.h>
#endif


@interface CBL_Router (Handlers)
- (CBLStatus) do_GETRoot;
@end


@implementation CBL_Router


- (instancetype) initWithDatabaseManager: (CBLManager*)dbManager request: (NSURLRequest*)request {
    NSParameterAssert(request);
    self = [super init];
    if (self) {
        _dbManager = dbManager;
        _request = request;
        _response = [[CBLResponse alloc] init];
        _local = YES;
        _processRanges = YES;
        if (0) { // assignments just to appease static analyzer so it knows these ivars are used
            _longpoll = _changesIncludeDocs = _changesIncludeConflicts = NO;
            _changesFilter = NULL;
            _changesFilterParams = nil;
        }
    }
    return self;
}

- (instancetype) initWithServer: (CBL_Server*)server
                        request: (NSURLRequest*)request
                        isLocal: (BOOL)isLocal
{
    NSParameterAssert(server);
    NSParameterAssert(request);
    self = [self initWithDatabaseManager: nil request: request];
    if (self) {
        _server = server;
        _local = isLocal;
        _processRanges = YES;
    }
    return self;
}

- (void)dealloc {
    [self stopNow];
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
    return [[(self.queries)[param] stringByReplacingOccurrencesOfString:@"+" withString:@" "]
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
    id result = [CBLJSON JSONObjectWithData: [value dataUsingEncoding: NSUTF8StringEncoding]
                                   options: CBLJSONReadingAllowFragments
                                     error: outError];
    if (!result)
        Warn(@"CBL_Router: invalid JSON in query param ?%@=%@", param, value);
    return result;
}


- (BOOL) cacheWithEtag: (NSString*)etag {
    NSString* eTag = $sprintf(@"\"%@\"", etag);
    _response[@"Etag"] = eTag;
    return $equal(eTag, [_request valueForHTTPHeaderField: @"If-None-Match"]);
}


- (NSDictionary*) bodyAsDictionary {
    return $castIf(NSDictionary, [CBLJSON JSONObjectWithData: _request.HTTPBody
                                                    options: 0 error: NULL]);
}


- (CBLContentOptions) contentOptions {
    CBLContentOptions options = 0;
    if ([self boolQuery: @"attachments"])
        options |= kCBLIncludeAttachments;
    if ([self boolQuery: @"local_seq"])
        options |= kCBLIncludeLocalSeq;
    if ([self boolQuery: @"conflicts"])
        options |= kCBLIncludeConflicts;
    if ([self boolQuery: @"revs"])
        options |= kCBLIncludeRevs;
    if ([self boolQuery: @"revs_info"])
        options |= kCBLIncludeRevsInfo;
    return options;
}


// Kludge that makes sure a query parameter doesn't get prematurely dealloced.
- (id) retainQuery: (id)query {
    if (query) {
        if (!_queryRetainer)
            _queryRetainer = [[NSMutableArray alloc] init];
        [_queryRetainer addObject: query];
    }
    return query;
}


- (CBLQueryOptions*) getQueryOptions {
    // http://wiki.apache.org/couchdb/HTTP_view_API#Querying_Options
    CBLQueryOptions* options = [CBLQueryOptions new];
    options->skip = [self intQuery: @"skip" defaultValue: options->skip];
    options->limit = [self intQuery: @"limit" defaultValue: options->limit];
    options->groupLevel = [self intQuery: @"group_level" defaultValue: options->groupLevel];
    options->descending = [self boolQuery: @"descending"];
    options->includeDocs = [self boolQuery: @"include_docs"];
    if ([self boolQuery: @"include_deleted"])
        options->allDocsMode = kCBLIncludeDeleted;
    else if ([self boolQuery: @"include_conflicts"]) // nonstandard
        options->allDocsMode = kCBLShowConflicts;
    else if ([self boolQuery: @"only_conflicts"]) // nonstandard
        options->allDocsMode = kCBLOnlyConflicts;
    options->updateSeq = [self boolQuery: @"update_seq"];
    if ([self query: @"inclusive_end"])
        options->inclusiveEnd = [self boolQuery: @"inclusive_end"];
    if ([self query: @"inclusive_start"])
        options->inclusiveStart = [self boolQuery: @"inclusive_start"]; // nonstandard
    options->prefixMatchLevel = [self intQuery: @"prefix_match_level" // nonstandard
                                  defaultValue: options->prefixMatchLevel];
    options->reduceSpecified = [self query: @"reduce"] != nil;
    options->reduce =  [self boolQuery: @"reduce"];
    options->group = [self boolQuery: @"group"];
    options->content = [self contentOptions];

    // Handle 'keys' and 'key' options:
    NSError* error = nil;
    id keys = [self jsonQuery: @"keys" error: &error];
    if (error || (keys && ![keys isKindOfClass: [NSArray class]]))
        return nil;
    if (!keys) {
        id key = [self jsonQuery: @"key" error: &error];
        if (error)
            return nil;
        if (key)
            keys = @[key];
    }
    
    if (keys) {
        options.keys = [self retainQuery: keys];
    } else {
        // Handle 'startkey' and 'endkey':
        options.startKey = [self retainQuery: [self jsonQuery: @"startkey" error: &error]];
        if (error)
            return nil;
        options.endKey = [self retainQuery: [self jsonQuery: @"endkey" error: &error]];
        if (error)
            return nil;
        options.startKeyDocID = [self retainQuery: [self jsonQuery: @"startkey_docid" error: &error]];
        if (error)
            return nil;
        options.endKeyDocID = [self retainQuery: [self jsonQuery: @"endkey_docid" error: &error]];
        if (error)
            return nil;
    }

    // Nonstandard full-text search options 'full_text', 'snippets', 'ranking':
    options.fullTextQuery = [self retainQuery: [self query: @"full_text"]];
    options->fullTextSnippets = [self boolQuery: @"snippets"];
    if ([self query: @"ranking"])
        options->fullTextRanking = [self boolQuery: @"ranking"];

    // Nonstandard geo-query option 'bbox':
    NSString* bboxString = [self query: @"bbox"];
    if (bboxString) {
        CBLGeoRect bbox;
        if (!CBLGeoCoordsStringToRect(bboxString, &bbox))
            return nil;
        NSData* savedBbox = [NSData dataWithBytes: &bbox length: sizeof(bbox)];
        [_queryRetainer addObject: savedBbox];
        options->bbox = savedBbox.bytes;
    }

    return options;
}


- (BOOL) explicitlyAcceptsType: (NSString*)mimeType {
    NSString* accept = [_request valueForHTTPHeaderField: @"Accept"];
    return accept && [accept rangeOfString: mimeType].length > 0;
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


- (CBLStatus) openDB {
    if (!_db.exists)
        return kCBLStatusNotFound;
    NSError* error;
    if (![_db open: &error])
        return CBLStatusFromNSError(error, kCBLStatusDBError);
    return kCBLStatusOK;
}


static NSArray* splitPath( NSURL* url ) {
    // Unfortunately can't just call url.path because that converts %2F to a '/'.
#ifdef GNUSTEP
    NSString* pathString = [url pathWithEscapes];
#else
    #ifdef __OBJC_GC__
    NSString* pathString = NSMakeCollectable(CFURLCopyPath((CFURLRef)url));
    #else
    NSString* pathString = (__bridge_transfer NSString *)CFURLCopyPath((__bridge CFURLRef)url);
    #endif
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
#endif
    return path;
}


- (CBLStatus) route {
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
        return kCBLStatusBadRequest;
        
    NSUInteger pathLen = _path.count;
    if (pathLen > 0) {
        NSString* dbName = _path[0];
        BOOL validName = [CBLManager isValidDatabaseName: dbName];
        if ([dbName hasPrefix: @"_"] && !validName) {
            [message appendString: dbName]; // special root path, like /_all_dbs
        } else if (!validName) {
            return kCBLStatusBadID;
        } else {
            // Instantiate the db object but don't create/open the file yet
            _db = [_dbManager _databaseNamed: dbName mustExist: NO error: NULL];
            if (!_db)
                return kCBLStatusNotFound;
            [message appendString: @":"];
        }
    } else {
        [message appendString: @"Root"];
    }
    
    NSString* docID = nil;
    if (_db && pathLen > 1) {
        // Make sure database exists, then interpret doc name:
        CBLStatus status = [self openDB];
        if (CBLStatusIsError(status))
            return status;
        NSString* name = _path[1];
        if (![name hasPrefix: @"_"]) {
            // Regular document
            if (![CBLDatabase isValidDocumentID: name])
                return kCBLStatusBadID;
            docID = name;
        } else if ([name isEqualToString: @"_design"] || [name isEqualToString: @"_local"]) {
            // "_design/____" and "_local/____" are document names
            if (pathLen <= 2)
                return kCBLStatusNotFound;
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
        Log(@"CBL_Router: unknown request type: %@ %@ (mapped to %@)",
             _request.HTTPMethod, _request.URL.path, message);
        Assert([self respondsToSelector: @selector(do_GETRoot)],
               @"CBL_Router(Handlers) is missing -- app may be linked without -ObjC linker flag.");
        sel = @selector(do_UNKNOWN);
    }
    
    if (_onAccessCheck) {
        CBLStatus status = _onAccessCheck(_db, docID, sel);
        if (CBLStatusIsError(status)) {
            LogTo(CBL_Router, @"Access check failed for %@", _db.name);
            return status;
        }
    }

    // Send 'sel' to self, i.e. call the method it names. This is equivalent to -performSelector,
    // which isn't legal under ARC.
    // The parameters are the database, doc ID and attachment name; any of these can be missing in
    // the actual method since C allows unhandled parameters.
    IMP imp = [self methodForSelector: sel];
    CBLStatus (*methodImpl)(id, SEL, CBLDatabase*, NSString*, NSString*) = (void *)imp;
    return methodImpl(self, sel, _db, docID, attachmentName);
}


- (void) run {
    if (WillLogTo(CBL_Router)) {
        NSMutableString* output = [NSMutableString stringWithFormat: @"%@ %@",
                                   _request.HTTPMethod, _request.URL.my_sanitizedString];
        if (_request.HTTPBodyStream)
            [output appendString: @" + body stream"];
        else if (_request.HTTPBody.length > 0)
            [output appendFormat: @" + %llu-byte body", (uint64_t)_request.HTTPBody.length];
        NSDictionary* headers = _request.allHTTPHeaderFields;
        for (NSString* key in headers)
            [output appendFormat: @"\n\t%@: %@", key, headers[key]];
        LogTo(CBL_Router, @"%@", output);
    }
    
    Assert(_dbManager);
    // Call the appropriate handler method:
    CBLStatus status;
    @try {
        status = [self route];
    } @catch (NSException *x) {
        Warn(@"Exception caught in CBL_Router:\n\t%@\n%@", x, x.my_callStack);
        status = kCBLStatusException;
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
                                                     name: CBL_DatabaseWillCloseNotification
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
        regex = $regex(@"^bytes=(\\d+)?-(\\d+)?$");
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

    if (from == 0 && to == bodyLength - 1)
        return; // No-op; entire body still causes a 200 response

    body = [body subdataWithRange: NSMakeRange(from, to - from + 1)];
    _response.body = [CBL_Body bodyWithJSON: body];  // not actually JSON

    // Content-Range: http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.16
    NSString* contentRangeStr = $sprintf(@"bytes %llu-%llu/%llu",
                                         (uint64_t)from, (uint64_t)to, (uint64_t)bodyLength);
    _response[@"Content-Range"] = contentRangeStr;
    _response.status = 206; // Partial Content
    LogTo(CBL_Router, @"Content-Range: %@", contentRangeStr);
}


- (void) sendResponseHeaders {
    if (_responseSent)
        return;
    _responseSent = YES;

    _response[@"Server"] = $sprintf(@"CouchbaseLite %@", CBLVersion());

    // Check for a mismatch between the Accept request header and the response type:
    NSString* accept = [_request valueForHTTPHeaderField: @"Accept"];
    if (accept && [accept rangeOfString: @"*/*"].length == 0) {
        NSString* responseType = _response.baseContentType;
        if (responseType && [accept rangeOfString: responseType].length == 0) {
            LogTo(CBL_Router, @"Error kCBLStatusNotAcceptable: Can't satisfy request Accept: %@"
                               " (actual type is %@)", accept, responseType);
            [_response reset];
            _response.internalStatus = kCBLStatusNotAcceptable;
        }
    }
    
    // When response body is not nil and there is no content-type given,
    // set default value to 'application/json'.
    if (_response.body && !_response[@"Content-Type"]) {
        _response[@"Content-Type"] = @"application/json";
    }
    
    if (_response.status == 200 && ($equal(_request.HTTPMethod, @"GET") ||
                                    $equal(_request.HTTPMethod, @"HEAD"))) {
        if (!_response[@"Cache-Control"])
            _response[@"Cache-Control"] = @"must-revalidate";
    }

    for (NSString *key in [_server.customHTTPHeaders allKeys]) {
        _response[key] = _server.customHTTPHeaders[key];
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
    if (WillLogTo(CBL_Router)) {
        NSMutableString* output = [NSMutableString stringWithFormat: @"Response -- status=%d, body=%llu bytes",
                                   _response.status, (uint64_t)_response.body.asJSON.length];
        NSDictionary* headers = _response.headers;
        for (NSString* key in headers)
            [output appendFormat: @"\n\t%@: %@", key, headers[key]];
        LogTo(CBL_Router, @"%@", output);
    }
    OnFinishedBlock onFinished = _onFinished;
    [self stopNow];
    if (onFinished)
        onFinished();
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
        [_server tellDatabaseManager: ^(CBLManager* dbm) {
            _dbManager = dbm;
            [self run];
        }];
    }
}


- (CBLStatus) do_UNKNOWN {
    return kCBLStatusNotFound;
}


- (void) dbClosing: (NSNotification*)n {
    LogTo(CBL_Router, @"Database closing! Returning error 500");
    if (!_responseSent) {
        _response.internalStatus = 500;
        [self sendResponseHeaders];
    }
    [self finished];
}


@end


#pragma mark - CBLRESPONSE

@implementation CBLResponse

- (instancetype) init {
    self = [super init];
    if (self) {
        _status = kCBLStatusOK;
        _headers = [[NSMutableDictionary alloc] init];
    }
    return self;
}


- (void) reset {
    [_headers removeAllObjects];
    _body = nil;
}

@synthesize status=_status, internalStatus=_internalStatus, statusMsg=_statusMsg,
            statusReason=_statusReason, headers=_headers, body=_body;

- (void) setInternalStatus:(CBLStatus)internalStatus {
    _internalStatus = internalStatus;
    NSString* statusMsg;
    self.status = CBLStatusToHTTPStatus(internalStatus, &statusMsg);
    _statusMsg = statusMsg;
    if (_status < 300) {
        if (!_body && !_headers[@"Content-Type"]) {
            self.body = [CBL_Body bodyWithJSON:
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
    self.body = bodyObject ? [CBL_Body bodyWithProperties: bodyObject] : nil;
}

- (void) setMultipartBody: (CBLMultipartWriter*)mp {
    // OPT: Would be better to stream this than shoving all the data into _body.
    self.body = [CBL_Body bodyWithJSON: mp.allOutput];
    self[@"Content-Type"] = mp.contentType;
}

- (void) setMultipartBody: (NSArray*)parts type: (NSString*)type {
    CBLMultipartWriter* mp = [[CBLMultipartWriter alloc] initWithContentType: type
                                                                      boundary: nil];
    for (__strong id part in parts) {
        if (![part isKindOfClass: [NSData class]]) {
            part = [CBLJSON dataWithJSONObject: part options: 0 error: NULL];
            [mp setNextPartsHeaders: $dict({@"Content-Type", @"application/json"})];
        }
        [mp addData: part];
    }
    [self setMultipartBody: mp];
}

@end
