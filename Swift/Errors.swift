//
//  Errors.swift
//  CBL ObjC
//
//  Copyright (c) 2021 Couchbase  Inc All rights reserved.
//
//  Licensed under the Apache License  Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing  software
//  distributed under the License is distributed on an "AS IS" BASIS
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND  either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//


import Foundation

/// Domain for Couchbase Lite errors.
public let ErrorDomain = CBLErrorDomain

public enum CBLError: Int {
    /// Internal assertion failure
    case assertionFailed = 1
    
    /// Oops  an unimplemented API call
    case unimplemented
    
    /// Unsupported encryption algorithm
    case unsupportedEncryption
    
    /// Invalid revision ID syntax
    case badRevisionID
    
    /// Document contains corrupted/unreadable data
    case corruptRevisionData
    
    /// Database/KeyStore/index is not open
    case notOpen
    
    /// Document not found
    case notFound
    
    /// Document update conflict
    case conflict
    
    /// Invalid function parameter or struct value
    case invalidParameter
    
    /// Internal unexpected C++ exception
    case unexpectedError  = 10
    
    /// Database file can't be opened; may not exist
    case cantOpenFile
    
    /// File I/O error
    case ioError
    
    /// Memory allocation failed (out of memory?)
    case memoryError
    
    /// File is not writeable
    case notWriteable
    
    /// Data is corrupted
    case corruptData
    
    /// Database is busy/locked
    case busy
    
    /// Function must be called while in a transaction
    case notInTransaction
    
    /// Database can't be closed while a transaction is open
    case transactionNotClosed
    
    /// Operation not supported in this database
    case unsupported
    
    /// File is not a database  or encryption key is wrong
    case unreadableDatabase = 20
    
    /// Database exists but not in the format/storage requested
    case wrongFormat
    
    /// Encryption/decryption error
    case crypto
    
    /// Invalid query
    case invalidQuery
    
    /// No such index  or query requires a nonexistent index
    case missingIndex
    
    /// Unknown query param name  or param number out of range
    case invalidQueryParam
    
    /// Unknown error from remote server
    case remoteError
    
    /// Database file format is older than what I can open
    case databaseTooOld
    
    /// Database file format is newer than what I can open
    case databaseTooNew
    
    /// Invalid document ID
    case badDocID
    
    /// Database can't be upgraded (might be unsupported dev version)
    case cantUpgradeDatabase = 30
    
    // Note: These are equivalent to the C4Error codes declared in LiteCore's c4Base.h

    // MARK: -- Network error codes start here
    
    /// Network error codes start here
    case networkBase                 = 5000
    
    /// DNS lookup failed
    case dnsFailure                  = 5001
    
    /// DNS server doesn't know the hostname
    case unknownHost                 = 5002
    
    /// Socket timeout during an operation
    case timeout                     = 5003
    
    /// The provided url is not valid
    case invalidURL                  = 5004
    
    /// Too many HTTP redirects for the HTTP client to handle
    case tooManyRedirects            = 5005
    
    /// Failure during TLS handshake process
    case tlsHandshakeFailed          = 5006
    
    /// The provided TLS certificate has expired
    case tlsCertExpired              = 5007
    
    /// Cert isn't trusted for other reason
    case tlsCertUntrusted            = 5008
    
    /// A required client certificate was not provided
    case tlsClientCertRequired       = 5009
    
    /// Client certificate was rejected by the server
    case tlsClientCertRejected       = 5010
    
    /// Self-signed cert  or unknown anchor cert
    case tlsCertUnknownRoot          = 5011
    
    /// Attempted redirect to invalid replication endpoint by server
    case invalidRedirect             = 5012
    
    // MARK: -- HTTP status codes start here
    
    /// HTTP status codes start here
    case httpBase                    = 10000
    
    /// Missing or incorrect user authentication
    case httpAuthRequired            = 10401
    
    /// User doesn't have permission to access resource
    case httpForbidden               = 10403
    
    /// Resource not found
    case httpNotFound                = 10404
    
    /// Update conflict
    case httpConflict                = 10409
    
    /// HTTP proxy requires authentication
    case httpProxyAuthRequired       = 10407
    
    /// Data is too large to upload
    case httpEntityTooLarge          = 10413
    
    /// HTCPCP/1.0 error (RFC 2324)
    case httpImATeapot               = 10418
    
    /// Something's wrong with the server
    case httpInternalServerError     = 10500
    
    /// Unimplemented server functionality
    case httpNotImplemented          = 10501
    
    /// Service is down temporarily(?)
    case httpServiceUnavailable      = 10503
    
    // MARK: -- WebSocket status codes start here
    
    /// WebSocket status codes start here
    case webSocketBase               = 11000
    
    /// Peer has to close  e.g. because host app is quitting
    case webSocketGoingAway          = 11001
    
    /// Protocol violation: invalid framing data
    case webSocketProtocolError      = 11002
    
    /// Message payload cannot be handled
    case webSocketDataError          = 11003
    
    /// TCP socket closed unexpectedly
    case webSocketAbnormalClose      = 11006
    
    /// Unparseable WebSocket message
    case webSocketBadMessageFormat   = 11007
    
    /// Message violated unspecified policy
    case webSocketPolicyError        = 11008
    
    /// Message is too large for peer to handle
    case webSocketMessageTooBig      = 11009
    
    /// Peer doesn't provide a necessary extension
    case webSocketMissingExtension   = 11010
    
    /// Can't fulfill request due to "unexpected condition"
    case webSocketCantFulfill        = 11011
    
#if COUCHBASE_ENTERPRISE
    /// Recoverable messaging error
    case webSocketCloseUserTransient = 14001
    
    /// Non-recoverable messaging error
    case webSocketCloseUserPermanent = 14002
#endif
    
    /// Invalid JSON string error
    case invalidJSON                 = 17001
}

