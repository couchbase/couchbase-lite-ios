//
//  CBL_Replicator.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Replicator.h"
#import "CBJSONEncoder.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLManager.h"
#import "CBLFacebookAuthorizer.h"
#import "CBLOAuth1Authorizer.h"
#import "CBLPersonaAuthorizer.h"


@implementation CBL_ReplicatorSettings

@synthesize remote=_remote, isPush=_isPush, continuous=_continuous;
@synthesize createTarget=_createTarget;
@synthesize filterName=_filterName, filterParameters=_filterParameters, docIDs=_docIDs;
@synthesize options=_options, requestHeaders=_requestHeaders;
@synthesize revisionBodyTransformationBlock=_revisionBodyTransformationBlock;
@synthesize authorizer=_authorizer;


- (instancetype) initWithRemote: (NSURL*)remote push: (BOOL)push {
    self = [super init];
    if (self) {
        _remote = remote;
        _isPush = push;
    }
    return self;
}


/** This is the _local document ID stored on the remote server to keep track of state.
    It's based on the local database UUID (the private one, to make the result unguessable),
    the remote database's URL, and the filter name and parameters (if any). */
- (NSString*) remoteCheckpointDocIDForLocalUUID: (NSString*)localUUID {
    // Needs to be consistent with -hasSameSettingsAs: --
    // If a.remoteCheckpointID == b.remoteCheckpointID then [a hasSameSettingsAs: b]
    NSMutableDictionary* spec = $mdict({@"localUUID", localUUID},
                                       {@"remoteURL", _remote.absoluteString},
                                       {@"push", @(_isPush)},
                                       {@"continuous", (_continuous ? nil : $false)},
                                       {@"filter", _filterName},
                                       {@"filterParams", _filterParameters},
                                     //{@"headers", _requestHeaders}, (removed; see #143)
                                       {@"docids", _docIDs});
    NSError *error;
    NSString *remoteCheckpointDocID = CBLHexSHA1Digest([CBJSONEncoder canonicalEncoding: spec
                                                                         error: &error]);
    Assert(!error);
    return remoteCheckpointDocID;
}


- (BOOL) isEqual: (id)other {
    // Needs to be consistent with -remoteCheckpointDocIDForLocalUUID:
    // If a.remoteCheckpointID == b.remoteCheckpointID then [a isEqual: b]
    return [other isKindOfClass: [CBL_ReplicatorSettings class]]
        && $equal(_remote, [other remote]) && _isPush == [other isPush]
        && $equal([self remoteCheckpointDocIDForLocalUUID: @""],
                  [other remoteCheckpointDocIDForLocalUUID: @""]);
}


@end