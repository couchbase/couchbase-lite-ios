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
import CouchbaseLiteSwift_Private

public struct CBLError {
    public static let domain = CBLErrorDomain
    
    internal static func create(_ code: Int, description: String) -> NSError {
        NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey : description])
    }

    /// Internal assertion failure
    public static let assertionFailed       = 1
    
    /// Oops  an unimplemented API call
    public static let unimplemented         = 2
    
    /// Unsupported encryption algorithm
    public static let unsupportedEncryption = 3
    
    /// Invalid revision ID syntax
    public static let badRevisionID         = 4
    
    /// Document contains corrupted/unreadable data
    public static let corruptRevisionData   = 5
    
    /// Database/KeyStore/index is not open
    public static let notOpen               = 6
    
    /// Document not found
    public static let notFound              = 7
    
    /// Document update conflict
    public static let conflict              = 8
    
    /// Invalid function parameter or struct value
    public static let invalidParameter      = 9
    
    /// Internal unexpected C++ exception
    public static let unexpectedError       = 10
    
    /// Database file can't be opened; may not exist
    public static let cantOpenFile          = 11
    
    /// File I/O error
    public static let ioError               = 12
    
    /// Memory allocation failed (out of memory?)
    public static let memoryError           = 13
    
    /// File is not writeable
    public static let notWriteable          = 14
    
    /// Data is corrupted
    public static let corruptData           = 15
    
    /// Database is busy/locked
    public static let busy                  = 16
    
    /// Function must be called while in a transaction
    public static let notInTransaction      = 17
    
    /// Database can't be closed while a transaction is open
    public static let transactionNotClosed  = 18
    
    /// Operation not supported in this database
    public static let unsupported           = 19
    
    /// File is not a database  or encryption key is wrong
    public static let unreadableDatabase    = 20
    
    /// Database exists but not in the format/storage requested
    public static let wrongFormat           = 21
    
    /// Encryption/decryption error
    public static let crypto                = 22
    
    /// Invalid query
    public static let invalidQuery          = 23
    
    /// No such index  or query requires a nonexistent index
    public static let missingIndex          = 24
    
    /// Unknown query param name  or param number out of range
    public static let invalidQueryParam     = 25
    
    /// Unknown error from remote server
    public static let remoteError           = 26
    
    /// Database file format is older than what I can open
    public static let databaseTooOld        = 27
    
    /// Database file format is newer than what I can open
    public static let databaseTooNew        = 28
    
    /// Invalid document ID
    public static let badDocID              = 29
    
    /// Database can't be upgraded (might be unsupported dev version)
    public static let cantUpgradeDatabase   = 30
    
    // Note: These are equivalent to the C4Error codes declared in LiteCore's c4Base.h

    // MARK: -- Network error codes start here
    
    /// Network error codes start here
    public static let networkBase                 = 5000
    
    /// DNS lookup failed
    public static let dnsFailure                  = 5001
    
    /// DNS server doesn't know the hostname
    public static let unknownHost                 = 5002
    
    /// Socket timeout during an operation
    public static let timeout                     = 5003
    
    /// The provided url is not valid
    public static let invalidURL                  = 5004
    
    /// Too many HTTP redirects for the HTTP client to handle
    public static let tooManyRedirects            = 5005
    
    /// Failure during TLS handshake process
    public static let tlsHandshakeFailed          = 5006
    
    /// The provided TLS certificate has expired
    public static let tlsCertExpired              = 5007
    
    /// Cert isn't trusted for other reason
    public static let tlsCertUntrusted            = 5008
    
    /// A required client certificate was not provided
    public static let tlsClientCertRequired       = 5009
    
    /// Client certificate was rejected by the server
    public static let tlsClientCertRejected       = 5010
    
    /// Self-signed cert  or unknown anchor cert
    public static let tlsCertUnknownRoot          = 5011
    
    /// Attempted redirect to invalid replication endpoint by server
    public static let invalidRedirect             = 5012
    
    /// The specified network interface is not valid or unknown.
    public static let unknownInterface            = 5027
    
    // MARK: -- HTTP status codes start here
    
    /// HTTP status codes start here
    public static let httpBase                    = 10000
    
    /// Missing or incorrect user authentication
    public static let httpAuthRequired            = 10401
    
    /// User doesn't have permission to access resource
    public static let httpForbidden               = 10403
    
    /// Resource not found
    public static let httpNotFound                = 10404
    
    /// Update conflict
    public static let httpConflict                = 10409
    
    /// HTTP proxy requires authentication
    public static let httpProxyAuthRequired       = 10407
    
    /// Data is too large to upload
    public static let httpEntityTooLarge          = 10413
    
    /// HTCPCP/1.0 error (RFC 2324)
    public static let httpImATeapot               = 10418
    
    /// Something's wrong with the server
    public static let httpInternalServerError     = 10500
    
    /// Unimplemented server functionality
    public static let httpNotImplemented          = 10501
    
    /// Service is down temporarily(?)
    public static let httpServiceUnavailable      = 10503
    
    // MARK: -- WebSocket status codes start here
    
    /// WebSocket status codes start here
    public static let webSocketBase               = 11000
    
    /// Peer has to close  e.g. because host app is quitting
    public static let webSocketGoingAway          = 11001
    
    /// Protocol violation: invalid framing data
    public static let webSocketProtocolError      = 11002
    
    /// Message payload cannot be handled
    public static let webSocketDataError          = 11003
    
    /// TCP socket closed unexpectedly
    public static let webSocketAbnormalClose      = 11006
    
    /// Unparseable WebSocket message
    public static let webSocketBadMessageFormat   = 11007
    
    /// Message violated unspecified policy
    public static let webSocketPolicyError        = 11008
    
    /// Message is too large for peer to handle
    public static let webSocketMessageTooBig      = 11009
    
    /// Peer doesn't provide a necessary extension
    public static let webSocketMissingExtension   = 11010
    
    /// Can't fulfill request due to "unexpected condition"
    public static let webSocketCantFulfill        = 11011
    
#if COUCHBASE_ENTERPRISE
    /// Recoverable messaging error
    public static let webSocketCloseUserTransient = 14001
    
    /// Non-recoverable messaging error
    public static let webSocketCloseUserPermanent = 14002
#endif
    
    /// Invalid JSON string error
    public static let invalidJSON                 = 17001
    
    /// Error while decoding `Decodable` type
    public static let decodingError               = 18001
    /// Error while encoding `Encodable` type
    public static let encodingError               = 18002
}

