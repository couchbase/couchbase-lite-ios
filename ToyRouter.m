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
- (int) do_PUT: (ToyDB*)db docID: (NSString*)docID;
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
    return [self do_PUT: db docID: nil];
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


- (int) do_GET: (ToyDB*)db docID: (NSString*)docID {
    NSString* revID = [self query: @"rev"];
    ToyDocument* doc = [db getDocumentWithID: docID revisionID: revID];
    if (!doc)
        return 404;
    // TODO: Conditional GET!
    _response.body = doc;
    return 200;
}


- (int) do_PUT: (ToyDB*)db docID: (NSString*)docID {
    ToyDocument* document = [ToyDocument documentWithJSON: _request.HTTPBody];
    int status;
    document = [db putDocument: document
                        withID: docID
                    revisionID: document.revisionID
                        status: &status];
    if (status < 300) {
        _response.bodyObject = $dict({@"ok", $true},
                                     {@"id", document.documentID},
                                     {@"rev", document.revisionID});
    }
    return status;
}


- (int) do_DELETE: (ToyDB*)db docID: (NSString*)docID {
    return [db deleteDocumentWithID: docID revisionID: [self query: @"rev"]];
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

static NSString* Send(ToyServer* server, NSString* method, NSString* path,
                      int expectedStatus, NSString* expectedResult) {
    NSURL* url = [NSURL URLWithString: [@"http://" stringByAppendingString: path]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    ToyRouter* router = [[ToyRouter alloc] initWithServer: server request: request];
    CAssert(router!=nil);
    ToyResponse* response = router.response;
    NSData* json = response.body.asJSON;
    NSString* result = nil;
    if (json)
        result = [[[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding] autorelease];
    Log(@"%@ %@ --> %d %@", method, path, response.status, result);
    CAssertEq(response.status, expectedStatus);
    if (expectedResult)
        CAssertEqual(result, expectedResult);
    [router release];
    return result;
}

TestCase(ToyRouter) {
    static NSString* const kTestPath = @"/tmp/ToyRouterTest";
    [[NSFileManager defaultManager] removeItemAtPath: kTestPath error: nil];
    NSError* error;
    ToyServer* server = [[ToyServer alloc] initWithDirectory: kTestPath error: &error];
    CAssert(server, @"Failed to create server: %@", error);
    
    Send(server, @"GET", @"/", 200, @"{\"ToyCouch\":\"welcome\",\"version\":\"0.1\"}");
    Send(server, @"GET", @"/_all_dbs", 200, @"[]");
    Send(server, @"GET", @"/non-existent", 404, nil);
    Send(server, @"GET", @"/BadName", 400, nil);
    Send(server, @"PUT", @"/", 400, nil);
    Send(server, @"POST", @"/", 400, nil);

    Send(server, @"PUT", @"/database", 201, nil);
    Send(server, @"GET", @"/database", 200, 
         @"{\"db_name\":\"database\",\"num_docs\":0,\"update_seq\":0}");
    Send(server, @"PUT", @"/database", 412, nil);
    Send(server, @"PUT", @"/database2", 201, nil);
    Send(server, @"GET", @"/database2", 200, 
         @"{\"db_name\":\"database2\",\"num_docs\":0,\"update_seq\":0}");
    Send(server, @"DELETE", @"/database2", 200, nil);
    Send(server, @"GET", @"/_all_dbs", 200, @"[\"database\"]");

    [server close];
    [server release];
}
#endif
