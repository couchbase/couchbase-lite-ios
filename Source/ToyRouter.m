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
#import "ToyRev.h"
#import "ToyServer.h"
#import "CollectionUtils.h"
#import "Logging.h"


NSString* const kToyVersionString =  @"0.1";


@interface ToyRouter ()
- (ToyDBStatus) update: (ToyDB*)db docID: (NSString*)docID json: (NSData*)json;
@end


@implementation ToyRouter

- (id) initWithServer: (ToyServer*)server request: (NSURLRequest*)request {
    NSParameterAssert(server);
    NSParameterAssert(request);
    self = [super init];
    if (self) {
        _server = [server retain];
        _request = [request retain];
        _response = [[ToyResponse alloc] init];
    }
    return self;
}

- (void)dealloc {
    [self stop];
    [_server release];
    [_request release];
    [_response release];
    [_queries release];
    [_onResponseReady release];
    [_onDataAvailable release];
    [_onFinished release];
    [super dealloc];
}


@synthesize onResponseReady=_onResponseReady, onDataAvailable=_onDataAvailable,
            onFinished=_onFinished, response=_response;


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


- (ToyDBStatus) openDB {
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


- (void) sendResponse {
    if (!_responseSent) {
        _responseSent = YES;
        if (_onResponseReady)
            _onResponseReady(_response);
    }
}


- (void) start {
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
        ToyDBStatus status = [self openDB];
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
    ToyDBStatus status = (ToyDBStatus) [self performSelector: sel withObject: _db withObject: docID];
    
    if (_response.bodyObject)
        [_response setValue: @"application/json" ofHeader: @"Content-Type"];
    //TODO: Add 'Date:' header
    
    // If response is ready (nonzero status), tell my client about it:
    if (status > 0) {
        _response.status = status;
        [self sendResponse];
        if (_onDataAvailable && _response.body) {
            _onDataAvailable(_response.body.asJSON);
        }
        if (_onFinished && !_waiting)
            _onFinished();
    }
}


- (void) stop {
    self.onResponseReady = nil;
    self.onDataAvailable = nil;
    self.onFinished = nil;
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (ToyDBStatus) do_UNKNOWN {
    return 400;
}


#pragma mark - SERVER REQUESTS:


- (ToyDBStatus) do_GETRoot {
    NSDictionary* info = $dict({@"ToyCouch", @"welcome"}, {@"version", kToyVersionString});
    _response.body = [ToyDocument documentWithProperties: info];
    return 200;
}

- (ToyDBStatus) do_GET_all_dbs {
    NSArray* dbs = _server.allDatabaseNames ?: $array();
    _response.body = [[[ToyDocument alloc] initWithArray: dbs] autorelease];
    return 200;
}


#pragma mark - DATABASE REQUESTS:


- (ToyDBStatus) do_GET: (ToyDB*)db {
    // http://wiki.apache.org/couchdb/HTTP_database_API#Database_Information
    ToyDBStatus status = [self openDB];
    if (status >= 300)
        return status;
    NSUInteger num_docs = db.documentCount;
    SequenceNumber update_seq = db.lastSequence;
    if (num_docs == NSNotFound || update_seq == NSNotFound)
        return 500;
    _response.bodyObject = $dict({@"db_name", db.name},
                                 {@"num_docs", $object(num_docs)},
                                 {@"update_seq", $object(update_seq)});
    return 200;
}


- (ToyDBStatus) do_PUT: (ToyDB*)db {
    if (db.exists)
        return 412;
    return [db open] ? 201 : 500;
}


- (ToyDBStatus) do_DELETE: (ToyDB*)db {
    return [_server deleteDatabaseNamed: db.name] ? 200 : 404;
}


- (ToyDBStatus) do_POST: (ToyDB*)db {
    ToyDBStatus status = [self openDB];
    if (status >= 300)
        return status;
    return [self update: db docID: [db generateDocumentID] json: _request.HTTPBody];
}


- (BOOL) getQueryOptions: (ToyDBQueryOptions*)options {
    // http://wiki.apache.org/couchdb/HTTP_view_API#Querying_Options
    *options = kDefaultToyDBQueryOptions;
    NSString* param = [self query: @"limit"];
    if (param)
        options->limit = param.intValue;
    param = [self query: @"skip"];
    if (param)
        options->skip = param.intValue;
    options->includeDocs = $equal([self query: @"include_docs"], @"true");
    options->updateSeq = $equal([self query: @"update_seq"], @"true");
    return YES;
}


- (ToyDBStatus) do_GET_all_docs: (ToyDB*)db {
    ToyDBQueryOptions options;
    if (![self getQueryOptions: &options])
        return 400;
    NSDictionary* result = [db getAllDocs: &options];
    if (!result)
        return 500;
    _response.bodyObject = result;
    return 200;
}


#pragma mark - CHANGES:


- (NSDictionary*) changeDictForRev: (ToyRev*)rev {
    return $dict({@"seq", $object(rev.sequence)},
                 {@"id",  rev.docID},
                 {@"changes", $array($dict({@"rev", rev.revID}))},
                 {@"deleted", rev.deleted ? $true : nil});
}


- (NSDictionary*) responseBodyForChanges: (NSArray*)changes since: (UInt64)since {
    NSArray* results = [changes my_map: ^(id rev) {return [self changeDictForRev: rev];}];
    if (changes.count > 0)
        since = [[changes lastObject] sequence];
    return $dict({@"results", results}, {@"last_seq", $object(since)});
}


- (void) sendContinuousChange: (ToyRev*)rev {
    NSDictionary* changeDict = [self changeDictForRev: rev];
    NSMutableData* json = [[NSJSONSerialization dataWithJSONObject: changeDict
                                                           options: 0 error: nil] mutableCopy];
    [json appendBytes: @"\n" length: 1];
    _onDataAvailable(json);
    [json release];
}


- (void) dbChanged: (NSNotification*)n {
    ToyRev* rev = [n.userInfo objectForKey: @"rev"];

    if (_longpoll) {
        Log(@"ToyRouter: Sending longpoll response");
        [self sendResponse];
        NSDictionary* body = [self responseBodyForChanges: $array(rev) since: 0];
        _onDataAvailable([NSJSONSerialization dataWithJSONObject: body
                                                         options: 0 error: nil]);
        _onFinished();
        [self stop];
    } else {
        Log(@"ToyRouter: Sending continous change chunk");
        [self sendContinuousChange: rev];
    }
}


- (ToyDBStatus) do_GET_changes: (ToyDB*)db {
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    ToyDBQueryOptions options;
    if (![self getQueryOptions: &options])
        return 400;
    int since = [[self query: @"since"] intValue];
    
    NSArray* changes = [db changesSinceSequence: since options: &options];
    if (!changes)
        return 500;
    
    NSString* feed = [self query: @"feed"];
    _longpoll = $equal(feed, @"longpoll");
    BOOL continuous = !_longpoll && $equal(feed, @"continuous");
    
    if (continuous || (_longpoll && changes.count==0)) {
        if (continuous) {
            [self sendResponse];
            for (ToyRev* rev in changes) 
                [self sendContinuousChange: rev];
        }
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(dbChanged:)
                                                     name: ToyDBChangeNotification
                                                   object: db];
        // Don't close connection; more data to come
        _waiting = YES;
        return 0;
    } else {
        _response.bodyObject = [self responseBodyForChanges: changes since: since];
        return 200;
    }
}


#pragma mark - DOCUMENT REQUESTS:


- (NSString*) setResponseEtag: (ToyRev*)rev {
    NSString* eTag = $sprintf(@"\"%@\"", rev.revID);
    [_response setValue: eTag ofHeader: @"Etag"];
    return eTag;
}


- (ToyDBStatus) do_GET: (ToyDB*)db docID: (NSString*)docID {
    ToyRev* rev = [db getDocumentWithID: docID revisionID: [self query: @"rev"]];
    if (!rev)
        return 404;
    
    // Check for conditional GET:
    NSString* eTag = [self setResponseEtag: rev];
    if ($equal(eTag, [_request valueForHTTPHeaderField: @"If-None-Match"]))
        return 304;
    
    _response.body = rev.document;
    return 200;
    //TODO: Handle ?_revs_info query
}


- (ToyDBStatus) update: (ToyDB*)db
         docID: (NSString*)docID
          json: (NSData*)json {
    ToyDocument* document = json ? [ToyDocument documentWithJSON: json] : nil;
    
    NSString* revID;
    if (document) {
        // PUT's revision ID comes from the JSON body.
        revID = document.revisionID;
    } else {
        // DELETE's revision ID can come either from the ?rev= query param or an If-Match header.
        revID = [self query: @"rev"];
        if (!revID) {
            NSString* ifMatch = [_request valueForHTTPHeaderField: @"If-Match"];
            if (ifMatch) {
                // Value of If-Match is an ETag, so have to trim the quotes around it:
                if (ifMatch.length > 2 && [ifMatch hasPrefix: @"\""] && [ifMatch hasSuffix: @"\""])
                    revID = [ifMatch substringWithRange: NSMakeRange(1, ifMatch.length-2)];
                else
                    return 400;
            }
        }
    }
    
    ToyRev* rev = [[[ToyRev alloc] initWithDocID: docID revID: nil deleted: !document] autorelease];
    if (!rev)
        return 400;
    rev.document = document;
    
    ToyDBStatus status;
    rev = [db putRevision: rev prevRevisionID: revID status: &status];
    if (status < 300) {
        [self setResponseEtag: rev];
        _response.bodyObject = $dict({@"ok", $true},
                                     {@"id", rev.docID},
                                     {@"rev", rev.revID});
    }
    return status;
}


- (ToyDBStatus) do_PUT: (ToyDB*)db docID: (NSString*)docID {
    NSData* json = _request.HTTPBody;
    if (!json)
        return 400;
    return [self update: db docID: docID json: json];
}


- (ToyDBStatus) do_DELETE: (ToyDB*)db docID: (NSString*)docID {
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
