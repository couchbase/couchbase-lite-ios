//
//  ToyRouter.m
//  ToyCouch
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyRouter.h"
#import "ToyDB.h"
#import "ToyDocument.h"
#import "ToyServer.h"
#import "CollectionUtils.h"
#import "Test.h"


#define kVersionString @"0.1"


@interface ToyRouter ()
- (int) update: (ToyDB*)db docID: (NSString*)docID json: (NSData*)json;
@end


@implementation ToyRouter

- (id) initWithServer: (ToyServer*)server request: (NSURLRequest*)request {
    NSParameterAssert(server);
    NSParameterAssert(request);
    self = [super init];
    if (self) {
        _server = [server retain];
        _request = [request retain];
    }
    return self;
}

- (void)dealloc {
    [_server release];
    [_request release];
    [_response release];
    [_queries release];
    [super dealloc];
}


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
    return [self.queries objectForKey: param];
}


- (int) openDB {
    if (!_db.exists)
        return 404;
    if (![_db open])
        return 500;
    return 200;
}


static NSArray* splitPath( NSString* path ) {
    NSMutableArray* items = $marray();
    for (NSString* item in [path componentsSeparatedByString: @"/"]) {
        if (item.length > 0)
            [items addObject: item];
    }
    return items;
}


- (void) route {
    // Refer to: http://wiki.apache.org/couchdb/Complete_HTTP_API_Reference
    
    NSMutableString* message = [NSMutableString stringWithFormat: @"do_%@", _request.HTTPMethod];
    
    // First interpret the components of the request:
    NSArray* path = splitPath(_request.URL.path);
    NSUInteger pathLen = path.count;
    if (pathLen > 0) {
        NSString* dbName = [path objectAtIndex: 0];
        if ([dbName hasPrefix: @"_"]) {
            [message appendString: dbName]; // special root path, like /_all_dbs
        } else {
            _db = [[_server databaseNamed: dbName] retain];
            if (!_db) {
                _response.status = 400;
                return;
            }
        }
    } else {
        [message appendString: @"Root"];
    }
    
    NSString* docID = nil;
    if (_db && pathLen > 1) {
        int status = [self openDB];
        if (status >= 300) {
            _response.status = status;
            return;
        }
        NSString* name = [path objectAtIndex: 1];
        if (![ToyDB isValidDocumentID: name]) {
            _response.status = 400;
            return;
        } else if ([name hasPrefix: @"_"]) {
            [message appendString: name];
        } else {
            docID = name;
        }
    }
    
    if (_db) {
        [message appendString: @":"];
        if (docID)
            [message appendString: @"docID:"];
    }
    
    // Send myself a message based on the components:
    SEL sel = NSSelectorFromString(message);
    if (!sel || ![self respondsToSelector: sel])
        sel = @selector(do_UNKNOWN);
    _response.status = (int) [self performSelector: sel withObject: _db withObject: docID];
    
    if (_response.bodyObject)
        [_response setValue: @"application/json" ofHeader: @"Content-Type"];
    //TODO: Add 'Date:' header
}

- (ToyResponse*) response {
    if (!_response) {
        _response = [[ToyResponse alloc] init];
        [self route];
    }
    return _response;
}

- (int) do_UNKNOWN {
    return 400;
}


#pragma mark - SERVER REQUESTS:


- (int) do_GETRoot {
    NSDictionary* info = $dict({@"ToyCouch", @"welcome"}, {@"version", kVersionString});
    _response.body = [ToyDocument documentWithProperties: info];
    return 200;
}

- (int) do_GET_all_dbs {
    NSArray* dbs = _server.allDatabaseNames ?: $array();
    _response.body = [[[ToyDocument alloc] initWithArray: dbs] autorelease];
    return 200;
}


#pragma mark - DATABASE REQUESTS:


- (int) do_GET: (ToyDB*)db {
    // http://wiki.apache.org/couchdb/HTTP_database_API#Database_Information
    int status = [self openDB];
    if (status >= 300)
        return status;
    NSUInteger num_docs = db.documentCount;
    NSUInteger update_seq = db.lastSequence;
    if (num_docs == NSNotFound || update_seq == NSNotFound)
        return 500;
    _response.bodyObject = $dict({@"db_name", db.name},
                                 {@"num_docs", $object(num_docs)},
                                 {@"update_seq", $object(update_seq)});
    return 200;
}


- (int) do_PUT: (ToyDB*)db {
    if (db.exists)
        return 412;
    return [db open] ? 201 : 500;
}


- (int) do_DELETE: (ToyDB*)db {
    return [_server deleteDatabaseNamed: db.name] ? 200 : 404;
}


- (int) do_POST: (ToyDB*)db {
    int status = [self openDB];
    if (status >= 300)
        return status;
    return [self update: db docID: nil json: _request.HTTPBody];
}


- (int) do_GET_changes: (ToyDB*)db {
    int since = [[self query: @"since"] intValue];
    NSArray* changes = [db changesSinceSequence: since];
    if (!changes)
        return 500;
    NSString* lastSeq = 0;
    if (changes.count > 0)
        lastSeq = [[changes lastObject] objectForKey: @"seq"];
    _response.bodyObject = $dict({@"results", changes}, {@"last_seq", lastSeq});
    return 200;
}


#pragma mark - DOCUMENT REQUESTS:


- (NSString*) setResponseEtag: (ToyDocument*)doc {
    NSString* eTag = $sprintf(@"\"%@\"", doc.revisionID);
    [_response setValue: eTag ofHeader: @"Etag"];
    return eTag;
}


- (int) do_GET: (ToyDB*)db docID: (NSString*)docID {
    ToyDocument* document = [db getDocumentWithID: docID
                                       revisionID: [self query: @"rev"]];
    if (!document)
        return 404;
    
    // Check for conditional GET:
    NSString* eTag = [self setResponseEtag: document];
    if ($equal(eTag, [_request valueForHTTPHeaderField: @"If-None-Match"]))
        return 304;
    
    _response.body = document;
    return 200;
    //TODO: Handle ?_revs_info query
}


- (int) update: (ToyDB*)db docID: (NSString*)docID json: (NSData*)json {
    ToyDocument* document = json ? [ToyDocument documentWithJSON: json] : nil;
    
    // The revision ID can come either from the ?rev= query param or an If-Match header.
    NSString* revID = [self query: @"rev"];
    if (!revID) {
        NSString* ifMatch = [self query: @"If-Match"];
        if (ifMatch) {
            // Value of If-Match is an ETag, so have to trim the quotes around it:
            if (ifMatch.length > 2 && [ifMatch hasPrefix: @"\""] && [ifMatch hasSuffix: @"\""])
                revID = [ifMatch substringWithRange: NSMakeRange(1, ifMatch.length-2)];
            else
                return 400;
        }
    }
    
    int status;
    document = [db putDocument: document withID: docID revisionID: revID status: &status];
    if (status < 300) {
        [self setResponseEtag: document];
        _response.bodyObject = $dict({@"ok", $true},
                                     {@"id", document.documentID},
                                     {@"rev", document.revisionID});
    }
    return status;
}


- (int) do_PUT: (ToyDB*)db docID: (NSString*)docID {
    NSData* json = _request.HTTPBody;
    if (!json)
        return 400;
    return [self update: db docID: docID json: json];
}


- (int) do_DELETE: (ToyDB*)db docID: (NSString*)docID {
    return [self update: db docID: docID json: nil];
}


@end




@implementation ToyResponse

- (id) init
{
    self = [super init];
    if (self) {
        _status = 200;
        _headers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_headers release];
    [_body release];
    [super dealloc];
}

@synthesize status=_status, headers=_headers, body=_body;

- (void) setValue: (NSString*)value ofHeader: (NSString*)header {
    [_headers setValue: value forKey: header];
}

- (id) bodyObject {
    return self.body.asObject;
}

- (void) setBodyObject:(id)bodyObject {
    self.body = bodyObject ? [ToyDocument documentWithProperties: bodyObject] : nil;
}

@end




#if DEBUG
#pragma mark - TESTS

static id SendBody(ToyServer* server, NSString* method, NSString* path, id bodyObj,
               int expectedStatus, id expectedResult) {
    NSURL* url = [NSURL URLWithString: [@"toy://" stringByAppendingString: path]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    if (bodyObj) {
        NSError* error = nil;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject: bodyObj options:0 error:&error];
        CAssertNil(error);
    }
    ToyRouter* router = [[ToyRouter alloc] initWithServer: server request: request];
    CAssert(router!=nil);
    ToyResponse* response = router.response;
    NSData* json = response.body.asJSON;
    NSString* jsonStr = nil;
    id result = nil;
    if (json) {
        jsonStr = [[[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding] autorelease];
        CAssert(jsonStr);
        NSError* error;
        result = [NSJSONSerialization JSONObjectWithData: json options: 0 error: &error];
        CAssert(result, @"Couldn't parse JSON response: %@", error);
    }
    Log(@"%@ %@ --> %d %@", method, path, response.status, jsonStr);
    
    CAssertEq(response.status, expectedStatus);

    if (expectedResult)
        CAssertEqual(result, expectedResult);
    [router release];
    return result;
}

static id Send(ToyServer* server, NSString* method, NSString* path,
               int expectedStatus, id expectedResult) {
    return SendBody(server, method, path, nil, expectedStatus, expectedResult);
}

TestCase(ToyRouter_Server) {
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyRouterTest"];
    Send(server, @"GET", @"/", 200, $dict({@"ToyCouch", @"welcome"}, {@"version", kVersionString}));
    Send(server, @"GET", @"/_all_dbs", 200, $array());
    Send(server, @"GET", @"/non-existent", 404, nil);
    Send(server, @"GET", @"/BadName", 400, nil);
    Send(server, @"PUT", @"/", 400, nil);
    Send(server, @"POST", @"/", 400, nil);
}

TestCase(ToyRouter_Databases) {
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyRouterTest"];
    Send(server, @"PUT", @"/database", 201, nil);
    Send(server, @"GET", @"/database", 200,
         $dict({@"db_name", @"database"}, {@"num_docs", $object(0)}, {@"update_seq", $object(0)}));
    Send(server, @"PUT", @"/database", 412, nil);
    Send(server, @"PUT", @"/database2", 201, nil);
    Send(server, @"GET", @"/_all_dbs", 200, $array(@"database", @"database2"));
    Send(server, @"GET", @"/database2", 200,
         $dict({@"db_name", @"database2"}, {@"num_docs", $object(0)}, {@"update_seq", $object(0)}));
    Send(server, @"DELETE", @"/database2", 200, nil);
    Send(server, @"GET", @"/_all_dbs", 200, $array(@"database"));
}

TestCase(ToyRouter_Docs) {
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyRouterTest"];
    Send(server, @"PUT", @"/db", 201, nil);
    NSDictionary* result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), 
                                    201, nil);
    Log(@"PUT returned %@", result);
    NSString* revID = [result objectForKey: @"rev"];
    CAssert([revID hasPrefix: @"1-"]);

    result = SendBody(server, @"PUT", $sprintf(@"/db/doc1?rev=%@", revID),
                                    $dict({@"message", @"goodbye"}), 
                                    201, nil);
    Log(@"PUT returned %@", result);
    revID = [result objectForKey: @"rev"];
    CAssert([revID hasPrefix: @"2-"]);
    
    Send(server, @"GET", @"/db/doc1", 200,
         $dict({@"_id", @"doc1"}, {@"_rev", revID}, {@"message", @"goodbye"}));
    
    result = Send(server, @"DELETE", $sprintf(@"/db/doc1?rev=%@", revID), 200, nil);
    revID = [result objectForKey: @"rev"];
    CAssert([revID hasPrefix: @"3-"]);

    Send(server, @"GET", @"/db/doc1", 404, nil);

    result = Send(server, @"GET", @"/db/_changes", 200,
                  $dict({@"last_seq", $object(3)},
                        {@"results", $array($dict({@"id", @"doc1"},
                                                  {@"rev", revID},
                                                  {@"seq", $object(3)},
                                                  {@"deleted", $true}))}));
}

#endif
