//
//  CBLDefaults.m
//  CouchbaseLite
//
//  Copyright (c) 2024-present Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

// THIS IS AN AUTOGENERATED FILE, MANUAL CHANGES SHOULD BE EXPECTED TO
// BE OVERWRITTEN

#import "CBLDefaults.h"

#pragma mark - CBLDatabaseConfiguration

const BOOL kCBLDefaultDatabaseFullSync = NO;

const BOOL kCBLDefaultDatabaseMmapEnabled = YES;

#pragma mark - CBLLogFileConfiguration

const BOOL kCBLDefaultLogFileUsePlaintext = NO;

const BOOL kCBLDefaultLogFileUsePlainText = NO;

const uint64_t kCBLDefaultLogFileMaxSize = 524288;

const NSInteger kCBLDefaultLogFileMaxRotateCount = 1;

#pragma mark - CBLFileLogSink

const BOOL kCBLDefaultFileLogSinkUsePlaintext = NO;

const long long kCBLDefaultFileLogSinkMaxSize = 524288;

const NSInteger kCBLDefaultFileLogSinkMaxKeptFiles = 2;

#pragma mark - CBLFullTextIndexConfiguration

const BOOL kCBLDefaultFullTextIndexIgnoreAccents = NO;

#pragma mark - CBLReplicatorConfiguration

const CBLReplicatorType kCBLDefaultReplicatorType = kCBLReplicatorTypePushAndPull;

const BOOL kCBLDefaultReplicatorContinuous = NO;

const BOOL kCBLDefaultReplicatorAllowReplicatingInBackground = NO;

const NSTimeInterval kCBLDefaultReplicatorHeartbeat = 300;

const NSUInteger kCBLDefaultReplicatorMaxAttemptsSingleShot = 10;

const NSUInteger kCBLDefaultReplicatorMaxAttemptsContinuous = NSUIntegerMax;

const NSTimeInterval kCBLDefaultReplicatorMaxAttemptsWaitTime = 300;

const NSTimeInterval kCBLDefaultReplicatorMaxAttemptWaitTime = 300;

const BOOL kCBLDefaultReplicatorEnableAutoPurge = YES;

const BOOL kCBLDefaultReplicatorSelfSignedCertificateOnly = NO;

const BOOL kCBLDefaultReplicatorAcceptParentCookies = NO;

#ifdef COUCHBASE_ENTERPRISE

#pragma mark - CBLVectorIndexConfiguration

const BOOL kCBLDefaultVectorIndexIsLazy = NO;

const CBLScalarQuantizerType kCBLDefaultVectorIndexEncoding = kCBLSQ8;

const CBLDistanceMetric kCBLDefaultVectorIndexDistanceMetric = kCBLDistanceMetricEuclideanSquared;

const unsigned int kCBLDefaultVectorIndexMinTrainingSize = 0;

const unsigned int kCBLDefaultVectorIndexMaxTrainingSize = 0;

const unsigned int kCBLDefaultVectorIndexNumProbes = 0;

#pragma mark - CBLURLEndpointListenerConfiguration

const unsigned short kCBLDefaultListenerPort = 0;

const BOOL kCBLDefaultListenerDisableTls = NO;

const BOOL kCBLDefaultListenerReadOnly = NO;

const BOOL kCBLDefaultListenerEnableDeltaSync = NO;

#endif
