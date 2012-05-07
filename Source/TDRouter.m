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
        if (0) { // assignments just to appease static analyzer so it knows these ivars are used
            _longpoll = NO;
            _changesIncludeDocs = NO;
        }
    }
    return self;
}

- (id) initWithServer: (TDServer*)server request: (NSURLRequest*)request {
    NSParameterAssert(server);
    NSParameterAssert(request);
    self = [self initWithDatabaseManager: nil request: request];
    if (self) {
        _server = [server retain];
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
    [_onAccessCheck release];
    [_onResponseReady release];
    [_onDataAvailable release];
    [_onFinished release];
    [super dealloc];
}


@synthesize onAccessCheck=_onAccessCheck, onResponseReady=_onResponseReady,
            onDataAvailable=_onDataAvailable, onFinished=_onFinished,
            request=_request, response=_response;


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
                [queries setObject: value forKey: key];
            }
            _queries = [queries copy];
        }
    }
    return _queries;
}


- (NSString*) query: (NSString*)param {
    return [[self.queries objectForKey: param]
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


- (BOOL) cacheWithEtag: (NSString*)etag {
    NSString* eTag = $sprintf(@"\"%@\"", etag);
    [_response setValue: eTag ofHeader: @"Etag"];
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
        options->keys = $array(key);
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


- (void) sendResponse {
    if (!_responseSent) {
        _responseSent = YES;
        if (_onResponseReady)
            _onResponseReady(_response);
    }
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
        NSString* dbName = [_path objectAtIndex: 0];
        if ([dbName hasPrefix: @"_"] && ![TDDatabaseManager isValidDatabaseName: dbName]) {
            [message appendString: dbName]; // special root path, like /_all_dbs
        } else {
            _db = [[_dbManager databaseNamed: dbName] retain];
            if (!_db)
                return kTDStatusBadID;
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
        NSString* name = [_path objectAtIndex: 1];
        if (![name hasPrefix: @"_"]) {
            // Regular document
            if (![TDDatabase isValidDocumentID: name])
                return kTDStatusBadID;
            docID = name;
        } else if ([name isEqualToString: @"_design"] || [name isEqualToString: @"_local"]) {
            // "_design/____" and "_local/____" are document names
            if (pathLen <= 2)
                return kTDStatusNotFound;
            docID = [name stringByAppendingPathComponent: [_path objectAtIndex: 2]];
            [_path replaceObjectAtIndex: 1 withObject: docID];
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
        attachmentName = [_path objectAtIndex: 2];
        if ([attachmentName hasPrefix: @"_"] && [docID hasPrefix: @"_design/"]) {
            // Design-doc attribute like _info or _view
            [message replaceOccurrencesOfString: @":docID:" withString: @":designDocID:"
                                        options:0 range: NSMakeRange(0, message.length)];
            docID = [docID substringFromIndex: 8];  // strip the "_design/" prefix
            [message appendString: [attachmentName substringFromIndex: 1]];
            [message appendString: @":"];
            attachmentName = pathLen > 3 ? [_path objectAtIndex: 3] : nil;
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
    
    // Check for a mismatch between the Accept request header and the response type:
    NSString* accept = [_request valueForHTTPHeaderField: @"Accept"];
    if (accept && !$equal(accept, @"*/*")) {
        NSString* responseType = _response.baseContentType;
        if (responseType && [accept rangeOfString: responseType].length == 0) {
            LogTo(TDRouter, @"Error kTDStatusNotAcceptable: Can't satisfy request Accept: %@", accept);
            status = kTDStatusNotAcceptable;
            [_response reset];
        }
    }

    [_response.headers setObject: $sprintf(@"TouchDB %g", TouchDBVersionNumber)
                          forKey: @"Server"];

    if (_response.body.isValidJSON)
        [_response setValue: @"application/json" ofHeader: @"Content-Type"];

    // If response is ready (nonzero status), tell my client about it:
    if (status > 0) {
        _response.internalStatus = status;
        [self sendResponse];
        if (_onDataAvailable && _response.body) {
            _onDataAvailable(_response.body.asJSON, !_waiting);
        }
        if (!_waiting) 
            [self finished];
    }
    
    // If I will keep running asynchronously (i.e. a _changes feed handler), listen for the
    // database closing so I can stop then:
    if (_running)
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbClosing:)
                                                     name: TDDatabaseWillCloseNotification
                                                   object: _db];
}


- (void) finished {
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
    if (_responseSent) {
        _response.internalStatus = 500;
        [self sendResponse];
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
    [_headers release];
    [_body release];
    [super dealloc];
}

- (void) reset {
    [_headers removeAllObjects];
    setObj(&_body, nil);
}

@synthesize status=_status, internalStatus=_internalStatus, statusMsg=_statusMsg,
            headers=_headers, body=_body;

- (void) setInternalStatus:(TDStatus)internalStatus {
    _internalStatus = internalStatus;
    NSString* statusMsg;
    self.status = TDStatusToHTTPStatus(internalStatus, &statusMsg);
    setObjCopy(&_statusMsg, statusMsg);
    if (_status < 300) {
        if (!_body && ![_headers objectForKey: @"Content-Type"]) {
            self.body = [TDBody bodyWithJSON:
                                    [@"{\"ok\":true}" dataUsingEncoding: NSUTF8StringEncoding]];
        }
    } else {
        self.bodyObject = $dict({@"status", $object(_status)},
                                {@"error", statusMsg});
        [self setValue: @"application/json" ofHeader: @"Content-Type"];
    }
}

- (void) setValue: (NSString*)value ofHeader: (NSString*)header {
    [_headers setValue: value forKey: header];
}

- (NSString*) baseContentType {
    NSString* type = [_headers objectForKey: @"Content-Type"];
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
    [self setValue: mp.contentType ofHeader: @"Content-Type"];
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
