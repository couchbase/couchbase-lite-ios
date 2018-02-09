//
//  CBLErrors.h
//  CBL ObjC
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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
    CBLErrorAssertionFailed = 1,    // Internal assertion failure
    CBLErrorUnimplemented,          // Oops, an unimplemented API call
    CBLErrorNoSequences,            // This KeyStore does not support sequences
    CBLErrorUnsupportedEncryption,  // Unsupported encryption algorithm
    CBLErrorNoTransaction,          // Function must be called within a transaction
    CBLErrorBadRevisionID,          // Invalid revision ID syntax
    CBLErrorBadVersionVector,       // Invalid version vector syntax
    CBLErrorCorruptRevisionData,    // Revision contains corrupted/unreadable data
    CBLErrorCorruptIndexData,       // Index contains corrupted/unreadable data
    CBLErrorTokenizerError, /*10*/  // can't create text tokenizer for FTS
    CBLErrorNotOpen,                // Database/KeyStore/index is not open
    CBLErrorNotFound,               // Document not found
    CBLErrorDeleted,                // Document has been deleted
    CBLErrorConflict,               // Document update conflict
    CBLErrorInvalidParameter,       // Invalid function parameter or struct value
    CBLErrorDatabaseError,          // Lower-level database error (SQLite)
    CBLErrorUnexpectedError,        // Internal unexpected C++ exception
    CBLErrorCantOpenFile,           // Database file can't be opened; may not exist
    CBLErrorIOError,                // File I/O error
    CBLErrorCommitFailed, /*20*/    // Transaction commit failed
    CBLErrorMemoryError,            // Memory allocation failed (out of memory?)
    CBLErrorNotWriteable,           // File is not writeable
    CBLErrorCorruptData,            // Data is corrupted
    CBLErrorBusy,                   // Database is busy/locked
    CBLErrorNotInTransaction,       // Function cannot be called while in a transaction
    CBLErrorTransactionNotClosed,   // Database can't be closed while a transaction is open
    CBLErrorIndexBusy,              // (unused)
    CBLErrorUnsupported,            // Operation not supported in this database
    CBLErrorUnreadableDatabase,     // File is not a database, or encryption key is wrong
    CBLErrorWrongFormat, /*30*/     // Database exists but not in the format/storage requested
    CBLErrorCrypto,                 // Encryption/decryption error
    CBLErrorInvalidQuery,           // Invalid query
    CBLErrorMissingIndex,           // No such index, or query requires a nonexistent index
    CBLErrorInvalidQueryParam,      // Unknown query param name, or param number out of range
    CBLErrorRemoteError,            // Unknown error from remote server
    CBLErrorDatabaseTooOld,         // Database file format is older than what I can open
    CBLErrorDatabaseTooNew,         // Database file format is newer than what I can open
    CBLErrorBadDocID,               // Invalid document ID
    CBLErrorCantUpgradeDatabase,    // Database can't be upgraded (might be unsupported dev version)
    // Note: These are equivalent to the C4Error codes declared in LiteCore's c4Base.h

    CBLErrorHTTPBase                = 10000,    // ---- HTTP status codes start here
    CBLErrorHTTPAuthRequired        = 10401,    // Missing or incorrect user authentication
    CBLErrorHTTPForbidden           = 10403,    // User doesn't have permission to access resource
    CBLErrorHTTPNotFound            = 10404,    // Resource not found
    CBLErrorHTTPConflict            = 10409,    // Update conflict
    CBLErrorHTTPProxyAuthRequired   = 10407,    // HTTP proxy requires authentication
    CBLErrorHTTPEntityTooLarge      = 10413,    // Data is too large to upload
    CBLErrorHTTPImATeapot           = 10418,    // HTCPCP/1.0 error (RFC 2324)
    CBLErrorHTTPInternalServerError = 10500,    // Something's wrong with the server
    CBLErrorHTTPNotImplemented      = 10501,    // Unimplemented server functionality
    CBLErrorHTTPServiceUnavailable  = 10503,    // Service is down temporarily(?)

    CBLErrorWebSocketBase             = 11000,  // ---- WebSocket status codes start here
    CBLErrorWebSocketGoingAway        = 11001,  // Peer has to close, e.g. because host app is quitting
    CBLErrorWebSocketProtocolError    = 11002,  // Protocol violation: invalid framing data
    CBLErrorWebSocketDataError        = 11003,  // Message payload cannot be handled
    CBLErrorWebSocketAbnormalClose    = 11006,  // TCP socket closed unexpectedly
    CBLErrorWebSocketBadMessageFormat = 11007,  // Unparseable WebSocket message
    CBLErrorWebSocketPolicyError      = 11008,  // Message violated unspecified policy
    CBLErrorWebSocketMessageTooBig    = 11009,  // Message is too large for peer to handle
    CBLErrorWebSocketMissingExtension = 11010,  // Peer doesn't provide a necessary extension
    CBLErrorWebSocketCantFulfill      = 11011,  // Can't fulfill request due to "unexpected condition"
};
