//
//  CBLCert.h
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

C4Cert* __nullable toC4Cert(NSArray* secCerts, NSError* _Nullable * error);

C4Cert* __nullable toC4Cert(SecIdentityRef identity, NSArray* _Nullable certs, NSError* _Nullable * error);

NSData* __nullable toPEM(NSArray* secCerts, NSError* _Nullable * error);

SecCertificateRef __nullable toSecCert(C4Cert* c4cert, NSError* _Nullable * error);

NSArray* __nullable toSecCertChain(C4Cert* c4cert, NSError* _Nullable * error);

NSArray* __nullable toSecIdentityWithCertChain(C4Cert* c4cert, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

NS_ASSUME_NONNULL_END
