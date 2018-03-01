//
//  Authenticator.swift
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

import Foundation

/// Authenticator objects provide server authentication credentials to the replicator.
/// Authenticator is a base opaque protocol; you must instantiate one of
/// its implementation.
public protocol Authenticator {
    // Opaque
}

/* internal */ protocol IAuthenticator: Authenticator {
    func toImpl() -> CBLAuthenticator;
}

/// The BasicAuthenticator class is an authenticator that will authenticate using HTTP Basic
/// auth with the given username and password. This should only be used over an SSL/TLS connection,
/// as otherwise it's very easy for anyone sniffing network traffic to read the password.
public struct BasicAuthenticator: IAuthenticator {
    
    /// The username.
    public let username: String
    
    
    /// The password.
    public let password: String
    
    
    // MARK: Internal
    
    
    func toImpl() -> CBLAuthenticator {
        return CBLBasicAuthenticator(username: username, password: password)
    }
    
}

/// The SessionAuthenticator class is an authenticator that will authenticate
/// by using the session ID of the session created by a Sync Gateway.
public struct SessionAuthenticator: IAuthenticator {
    
    /// Session ID of the session created by a Sync Gateway.
    public let sessionID: String
    
    
    /// Session cookie name that the session ID value will be set to when communicating
    /// the Sync Gateaway.
    public let cookieName: String
    
    
    /// Initializes with the Sync Gateway session ID and uses the default cookie name.
    ///
    /// - Parameter sessionID: Sync Gateway session ID.
    public init(sessionID: String) {
        self.init(sessionID: sessionID, cookieName: nil)
    }
    
    
    /// Initializes with the session ID and the cookie name. If the given cookieName
    /// is nil, the default cookie name will be used.
    ///
    /// - Parameters:
    ///   - sessionID: The Sync Gateway session ID.
    ///   - cookieName: The cookie name.
    public init(sessionID: String, cookieName: String?) {
        self.sessionID = sessionID
        self.cookieName = cookieName != nil ? cookieName! : defaultCookieName
    }
    
    
    // MARK: Internal
    
    
    let defaultCookieName = "SyncGatewaySession"
    
    func toImpl() -> CBLAuthenticator {
        return CBLSessionAuthenticator.init(sessionID: sessionID, cookieName: self.cookieName)
    }
    
}
