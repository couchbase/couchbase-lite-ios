//
//  CBL_ReplicatorSettings.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_ReplicatorSettings.h"
#import "CBL_Replicator.h"
#import "CBLDatabase+Internal.h"
#import "CBLRevision.h"
#import "CBLDocument.h"
#import "CBL_Revision.h"
#import "CBJSONEncoder.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLManager.h"
#import "CBLFacebookAuthorizer.h"
#import "CBLOAuth1Authorizer.h"
#import "CBLPersonaAuthorizer.h"
#import "CBLReachability.h"
#import "MYAnonymousIdentity.h"
#import <CommonCrypto/CommonDigest.h>


DefineLogDomain(Sync);
DefineLogDomain(SyncPerf);


#define kDefaultRequestTimeout 60.0

/** Version number of the sync protocol the replicator uses. */
#define kSyncVersionString @"1.3"


@implementation CBL_ReplicatorSettings

@synthesize remote=_remote, isPush=_isPush, continuous=_continuous;
@synthesize createTarget=_createTarget;
@synthesize filterName=_filterName, filterBlock=_filterBlock, filterParameters=_filterParameters;
@synthesize docIDs=_docIDs, options=_options, requestHeaders=_requestHeaders;
@synthesize revisionBodyTransformationBlock=_revisionBodyTransformationBlock;
@synthesize authorizer=_authorizer, downloadAttachments=_downloadAttachments;


- (instancetype) initWithRemote: (NSURL*)remote push: (BOOL)push {
    self = [super init];
    if (self) {
        _remote = remote;
        _isPush = push;
        _downloadAttachments = YES;
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
                                       {@"push", @(_isPush)},
                                       {@"continuous", (_continuous ? nil : $false)},
                                       {@"filter", _filterName},
                                       {@"filterParams", _filterParameters},
                                     //{@"headers", _requestHeaders}, (removed; see #143)
                                       {@"docids", _docIDs});
    // If "remoteUUID" option is specified, use that instead of the remote URL:
    NSString* remoteUUID = _options[kCBLReplicatorOption_RemoteUUID];
    if (remoteUUID)
        spec[@"remoteUUID"] = remoteUUID;
    else
        spec[@"remoteURL"] = _remote.absoluteString;
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
        && _isPush == [other isPush]
        && $equal([self remoteCheckpointDocIDForLocalUUID: @""],
                  [other remoteCheckpointDocIDForLocalUUID: @""]);
}


- (NSTimeInterval) requestTimeout {
    id timeoutObj = _options[kCBLReplicatorOption_Timeout];
    if (!timeoutObj)
        return kDefaultRequestTimeout;
    NSTimeInterval timeout = [timeoutObj doubleValue] / 1000.0;
    return timeout > 0.0 ? timeout : kDefaultRequestTimeout;
}


- (NSTimeInterval) pollInterval {
    NSTimeInterval pollInterval = 0.0;
    if (_continuous) {
        NSNumber* pollObj = $castIf(NSNumber, _options[kCBLReplicatorOption_PollInterval]);
        if (pollObj) {
            pollInterval = pollObj.doubleValue / 1000.0;
            if (pollInterval < 30.0) {
                Warn(@"CBL_ReplicatorSettings: poll interval of %@ ms is too short!", pollObj);
                pollInterval = 0.0;
            }
        }
    }
    return pollInterval;
}


+ (NSString*) userAgentHeader {
    static NSString* sUserAgent;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_IPHONE
        const char* platform = "iOS";
#else
        const char* platform = "Mac OS X";
#endif
        NSString* commit;
        if (strlen(CBL_SOURCE_REVISION) > (0))
            commit = [NSString stringWithFormat:@"/%s", CBL_SOURCE_REVISION];
        else
            commit = @"";
        sUserAgent = $sprintf(@"CouchbaseLite/%@ (%s %s%@)",
                              kSyncVersionString, platform, CBL_VERSION_STRING, commit);
    });
    return sUserAgent;
}


- (BOOL) canUseCellNetwork {
    NSString* network = [$castIf(NSString, _options[kCBLReplicatorOption_Network]) lowercaseString];
    return network == nil || $equal(network, @"cell") || $equal(network, @"!wifi");
}


- (BOOL) isHostReachable: (CBLReachability*)reachability {
    BOOL reachable = reachability.reachable;
    if (!reachable)
        return NO;
    // Parse "network" option. Could be nil or "WiFi" or "!Wifi" or "cell" or "!cell".
    NSString* network = [$castIf(NSString, _options[kCBLReplicatorOption_Network])
                         lowercaseString];
    if (network) {
        BOOL wifi = reachability.reachableByWiFi;
        if ($equal(network, @"wifi") || $equal(network, @"!cell"))
            reachable = wifi;
        else if ($equal(network, @"cell") || $equal(network, @"!wifi"))
            reachable = !wifi;
        else
            Warn(@"Unrecognized replication option \"network\"=\"%@\"", network);
    }
    return reachable;
}


- (BOOL) trustReachability {
    // Setting kCBLReplicatorOption_Network results to always trust
    // reachability result.
    if (_options[kCBLReplicatorOption_Network])
        return YES;
    id option = _options[kCBLReplicatorOption_TrustReachability];
    return option ? [option boolValue] : YES;
}


- (BOOL) checkSSLServerTrust: (SecTrustRef)trust
                     forHost: (NSString*)host
                        port: (UInt16)port
{
    NSData* pinnedCertData;
    id pin = _options[kCBLReplicatorOption_PinnedCert];
    if (pin) {
        // Pinned cert can be given as either NSData, hex NSString, or SecCertificateRef:
        if ([pin isKindOfClass: [NSData class]])
            pinnedCertData = pin;
        else if ([pin isKindOfClass: [NSString class]])
            pinnedCertData = CBLDataFromHex(pin);
        else if (CFGetTypeID((__bridge CFTypeRef)pin) == SecCertificateGetTypeID())
            pinnedCertData = CFAutorelease(SecCertificateCopyData((__bridge SecCertificateRef)pin));
        if (!pinnedCertData) {
            Warn(@"Invalid replicator %@ property value \"%@\"",
                 kCBLReplicatorOption_PinnedCert, pin);
            return NO;
        }
    }
    return CBLCheckSSLServerTrust(trust, host, port, pinnedCertData);
}


- (CBL_Revision*) transformRevision: (CBL_Revision*)rev {
    if(_revisionBodyTransformationBlock) {
        @try {
            CBL_Revision* xformed = _revisionBodyTransformationBlock(rev);
            if (xformed == nil)
                return nil;
            if (xformed != rev) {
                AssertEqual(xformed.docID, rev.docID);
                AssertEqual(xformed.revID, rev.revID);
                AssertEqual(xformed[@"_revisions"], rev[@"_revisions"]);
                if (xformed[@"_attachments"]) {
                    // Insert 'revpos' properties into any attachments added by the callback:
                    CBL_MutableRevision* mx = xformed.mutableCopy;
                    xformed = mx;
                    [mx mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *info) {
                        if (info[@"revpos"])
                            return info;
                        Assert(info[@"data"], @"Transformer added attachment without adding data");
                        NSMutableDictionary* nuInfo = info.mutableCopy;
                        nuInfo[@"revpos"] = @(rev.generation);
                        return nuInfo;
                    }];
                }
                rev = xformed;
            }
        }@catch (NSException* x) {
            Warn(@"%@: Exception transforming a revision of doc '%@': %@", self, rev.docID, x);
        }
    }
    return rev;
}


- (BOOL) compilePushFilterForDatabase: (CBLDatabase*)db status: (CBLStatus*)outStatus {
    if (!_isPush)
        return YES;
    if (_filterName) {
        _filterBlock = [db loadFilterNamed: _filterName status: outStatus];
        if (!_filterBlock) {
            Warn(@"%@: No filter '%@'", db, _filterName);
            return NO;
        }
    } else {
        NSArray* docIDs = _docIDs;
        if (docIDs) {
            _filterBlock = FILTERBLOCK({
                return [docIDs containsObject: revision.document.documentID];
            });
        }
    }
    return YES;
}


@end
