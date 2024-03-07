//
//  CBLErrors.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

#import <Foundation/Foundation.h>

/** NSError domain for Couchbase Lite errors. */
extern NSErrorDomain const CBLErrorDomain;

NS_ERROR_ENUM(CBLErrorDomain) {
    /** Internal assertion failure */
    CBLErrorAssertionFailed = 1,
    
    /** Oops, an unimplemented API call */
    CBLErrorUnimplemented,
    
    /** Unsupported encryption algorithm */
    CBLErrorUnsupportedEncryption,
    
    /** Invalid revision ID syntax */
    CBLErrorBadRevisionID,
    
    /** Document contains corrupted/unreadable data*/
    CBLErrorCorruptRevisionData,
    
    /** Database/KeyStore/index is not open */
    CBLErrorNotOpen,
    
    /** Document not found */
    CBLErrorNotFound,
    
    /** Document update conflict */
    CBLErrorConflict,
    
    /** Invalid function parameter or struct value*/
    CBLErrorInvalidParameter,
    
    /** Internal unexpected C++ exception */
    CBLErrorUnexpectedError  = 10,
    
    /** Database file can't be opened; may not exist */
    CBLErrorCantOpenFile,
    
    /** File I/O error */
    CBLErrorIOError,
    
    /** Memory allocation failed (out of memory?) */
    CBLErrorMemoryError,
    
    /** File is not writeable */
    CBLErrorNotWriteable,
    
    /** Data is corrupted */
    CBLErrorCorruptData,
    
    /** Database is busy/locked */
    CBLErrorBusy,
    
    /** Function must be called while in a transaction */
    CBLErrorNotInTransaction,
    
    /** Database can't be closed while a transaction is open */
    CBLErrorTransactionNotClosed,
    
    /** Operation not supported in this database */
    CBLErrorUnsupported,
    
    /** File is not a database, or encryption key is wrong */
    CBLErrorUnreadableDatabase = 20,
    
    /** Database exists but not in the format/storage requested */
    CBLErrorWrongFormat,
    
    /** Encryption/decryption error */
    CBLErrorCrypto,
    
    /** Invalid query */
    CBLErrorInvalidQuery,
    
    /** No such index, or query requires a nonexistent index */
    CBLErrorMissingIndex,
    
    /** Unknown query param name, or param number out of range */
    CBLErrorInvalidQueryParam,
    
    /** Unknown error from remote server */
    CBLErrorRemoteError,
    
    /** Database file format is older than what I can open */
    CBLErrorDatabaseTooOld,
    
    /** Database file format is newer than what I can open */
    CBLErrorDatabaseTooNew,
    
    /** Invalid document ID */
    CBLErrorBadDocID,
    
    /** Database can't be upgraded (might be unsupported dev version) */
    CBLErrorCantUpgradeDatabase = 30,
    
    // Note: These are equivalent to the C4Error codes declared in LiteCore's c4Base.h

#pragma mark -- Network error codes start here
    /** Network error codes start here */
    CBLErrorNetworkBase                 = 5000,
    
    /** DNS lookup failed */
    CBLErrorDNSFailure                  = 5001,
    
    /** DNS server doesn't know the hostname */
    CBLErrorUnknownHost                 = 5002,
    
    /** Socket timeout during an operation */
    CBLErrorTimeout                     = 5003,
    
    /** The provided url is not valid */
    CBLErrorInvalidURL                  = 5004,
    
    /** Too many HTTP redirects for the HTTP client to handle */
    CBLErrorTooManyRedirects            = 5005,
    
    /** Failure during TLS handshake process */
    CBLErrorTLSHandshakeFailed          = 5006,
    
    /** The provided TLS certificate has expired */
    CBLErrorTLSCertExpired              = 5007,
    
    /** Cert isn't trusted for other reason */
    CBLErrorTLSCertUntrusted            = 5008,
    
    /** A required client certificate was not provided */
    CBLErrorTLSClientCertRequired       = 5009,
    
    /** Client certificate was rejected by the server */
    CBLErrorTLSClientCertRejected       = 5010,
    
    /** Self-signed cert, or unknown anchor cert */
    CBLErrorTLSCertUnknownRoot          = 5011,
    
    /** Attempted redirect to invalid replication endpoint by server */
    CBLErrorInvalidRedirect             = 5012,
    
    /** The specified network interface is not valid or unknown. */
    CBLErrorUnknownInterface            = 5027,
    
#pragma mark -- HTTP status codes start here
    /** HTTP status codes start here*/
    CBLErrorHTTPBase                    = 10000,
    
    /** Missing or incorrect user authentication */
    CBLErrorHTTPAuthRequired            = 10401,
    
    /** User doesn't have permission to access resource */
    CBLErrorHTTPForbidden               = 10403,
    
    /** Resource not found */
    CBLErrorHTTPNotFound                = 10404,
    
    /** Update conflict */
    CBLErrorHTTPConflict                = 10409,
    
    /** HTTP proxy requires authentication */
    CBLErrorHTTPProxyAuthRequired       = 10407,
    
    /** Data is too large to upload */
    CBLErrorHTTPEntityTooLarge          = 10413,
    
    /** HTCPCP/1.0 error (RFC 2324) */
    CBLErrorHTTPImATeapot               = 10418,
    
    /** Something's wrong with the server */
    CBLErrorHTTPInternalServerError     = 10500,
    
    /** Unimplemented server functionality */
    CBLErrorHTTPNotImplemented          = 10501,
    
    /** Service is down temporarily(?) */
    CBLErrorHTTPServiceUnavailable      = 10503,

#pragma mark -- WebSocket status codes start here
    
    /** WebSocket status codes start here */
    CBLErrorWebSocketBase               = 11000,
    
    /** Peer has to close, e.g. because host app is quitting */
    CBLErrorWebSocketGoingAway          = 11001,
    
    /** Protocol violation: invalid framing data */
    CBLErrorWebSocketProtocolError      = 11002,
    
    /** Message payload cannot be handled */
    CBLErrorWebSocketDataError          = 11003,
    
    /** TCP socket closed unexpectedly */
    CBLErrorWebSocketAbnormalClose      = 11006,
    
    /** Unparseable WebSocket message */
    CBLErrorWebSocketBadMessageFormat   = 11007,
    
    /** Message violated unspecified policy */
    CBLErrorWebSocketPolicyError        = 11008,
    
    /** Message is too large for peer to handle */
    CBLErrorWebSocketMessageTooBig      = 11009,
    
    /** Peer doesn't provide a necessary extension */
    CBLErrorWebSocketMissingExtension   = 11010,
    
    /** Can't fulfill request due to "unexpected condition" */
    CBLErrorWebSocketCantFulfill        = 11011,
    
#ifdef COUCHBASE_ENTERPRISE
    /** Recoverable messaging error */
    CBLErrorWebSocketCloseUserTransient = 14001,
    
    /** Non-recoverable messaging error */
    CBLErrorWebSocketCloseUserPermanent = 14002,
#endif
    
    /** Invalid JSON string error */
    CBLErrorInvalidJSON                 = 17001,
};
