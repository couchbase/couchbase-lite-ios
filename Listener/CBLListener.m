//
//  CBLListener.m
//  CouchbaseLiteListener
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLListener.h"
#import "CBLHTTPServer.h"
#import "CBLHTTPConnection.h"
#import "CouchbaseLitePrivate.h"
#import "CBL_Server.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Internal.h"
#import "CBLManager+Internal.h"
#import "Logging.h"

#import "HTTPServer.h"
#import "HTTPLogging.h"


@interface CBLDDLogger : DDAbstractLogger
@end


@implementation CBLListener
{
    CBLHTTPServer* _httpServer;
    CBL_Server* _tdServer;
    CBLDatabase* _authDb;
    NSString* _realm;
    NSString* _authSecret;
    BOOL _readOnly;
    BOOL _requiresAuth;
    NSDictionary* _passwords;
    SecIdentityRef _SSLIdentity;
    NSArray* _SSLExtraCertificates;
}

NSString * const kcouch_httpd_auth_authentication_db = @"_users";

+ (void) initialize {
    if (self == [CBLListener class]) {
        if (WillLogTo(CBLListener)) {
            [DDLog addLogger:[[CBLDDLogger alloc] init]];
        }
    }
}


@synthesize readOnly=_readOnly, requiresAuth=_requiresAuth, realm=_realm, authSecret=_authSecret,
     SSLExtraCertificates=_SSLExtraCertificates;


- (instancetype) initWithManager: (CBLManager*)manager port: (UInt16)port {
    self = [super init];
    if (self) {
        _tdServer = manager.backgroundServer;
        _authDb = [manager _databaseNamed: kcouch_httpd_auth_authentication_db mustExist: NO error: NULL];
        _httpServer = [[CBLHTTPServer alloc] init];
        _httpServer.listener = self;
        _httpServer.tdServer = _tdServer;
        _httpServer.port = port;
        _httpServer.connectionClass = [CBLHTTPConnection class];
        self.realm = @"CouchbaseLite";
    }
    return self;
}


- (void)dealloc
{
    [self stop];
    if (_SSLIdentity)
        CFRelease(_SSLIdentity);
}


- (void) setBonjourName: (NSString*)name type: (NSString*)type {
    _httpServer.name = name;
    _httpServer.type = type;
}

- (NSDictionary *)TXTRecordDictionary                   {return _httpServer.TXTRecordDictionary;}
- (void)setTXTRecordDictionary:(NSDictionary *)dict     {_httpServer.TXTRecordDictionary = dict;}



- (BOOL) start: (NSError**)outError {
    return [_httpServer start: outError];
}

- (void) stop {
    [_httpServer stop];
}


- (UInt16) port {
    return _httpServer.listeningPort;
}


- (void) setPasswords: (NSDictionary*)passwords {
    _passwords = [passwords copy];
    _requiresAuth = (_passwords != nil);
}

- (NSString*) passwordForUser:(NSString *)username {
    return _passwords[username];
}


- (SecIdentityRef) SSLIdentity {
    return _SSLIdentity;
}

- (void) setSSLIdentity:(SecIdentityRef)identity {
    if (identity)
        CFRetain(identity);
    if (_SSLIdentity)
        CFRelease(_SSLIdentity);
    _SSLIdentity = identity;
}

- (NSDictionary *)getUserCreds:(NSString *)username {
    // We assume that the .passwords property takes the place of the
    // admin setup in local.ini, however these are not hashed
    if (_passwords && _passwords[username]) {
        return $dict({@"name", username},
                     {@"salt", nil},
                     {@"password", _passwords[username]},
                     {@"roles", @[@"admin"]});
    }
    
    NSArray *cachedUser = [self getFromCache:username];
    if (!cachedUser || !cachedUser[1]) {
        return nil;
    }
    
    return $dict({@"name", cachedUser[1][@"name"]},
                 {@"salt", cachedUser[1][@"salt"]},
                 {@"password_sha", cachedUser[1][@"password_sha"]},
                 {@"roles", cachedUser[1][@"roles"]});
}

    
- (NSArray *)getFromCache:(NSString *)username {
    // TODO: actually cache this, use time for expiry
    NSDictionary *dbUser = [self getUserFromDb:username];
    if (!dbUser) {
        return nil;
    } else {
        return @[username, dbUser, [NSDate date]];
    }
}

- (NSDictionary *)getUserFromDb:(NSString *)username {
    if (!_authDb)
      return nil;

    NSError* error;
    if (![_authDb open: &error]) {
        CBLStatus status = CBLStatusFromNSError(error, kCBLStatusDBError);
        LogTo(CBLListener, @"Authentication database (%@) cannot be opened '%d'", username, status);
        return nil;
    }
    
    CBLView* view = [_authDb viewNamed: @"byName"];
    [view setMapBlock: MAPBLOCK({
        id name = [doc objectForKey: @"name"];
        if (name) emit(name, doc);
    }) version: @"1.0"];
    
    CBLQuery* query = [[_authDb viewNamed: @"byName"] query];
    query.keys = @[ username ];
    query.limit = 1;
    
    for (CBLQueryRow* row in query.rows) {
        if ([[row.document getConflictingRevisions:NULL] count] > 1)
        {
            LogTo(CBLListener, @"User cannot be used for authentication as the document is currently in conflict '%@'", username);
            continue;
        }
        return row.documentProperties;
    }
    
    return nil;
}
    
@end


@implementation CBLHTTPServer

@synthesize listener=_listener, tdServer=_tdServer;

@end



// Adapter to output DDLog messages (from CocoaHTTPServer) via MYUtilities logging.
@implementation CBLDDLogger

- (void) logMessage:(DDLogMessage *)logMessage {
    Log(@"%@", logMessage->logMsg);
}

@end
