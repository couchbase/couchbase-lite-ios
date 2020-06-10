//
//  URLEndpontListenerTest.swift
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

import XCTest
@testable import CouchbaseLiteSwift

@available(macOS 10.12, iOS 10.0, *)
class URLEndpontListenerTest: ReplicatorTest {
    let wsPort: UInt16 = 4984
    let wssPort: UInt16 = 4985
    let serverCertLabel = "CBL-Server-Cert"
    let clientCertLabel = "CBL-Client-Cert"
    
    var listener: URLEndpointListener?
    
    @discardableResult
    func listen() throws -> URLEndpointListener {
        return try listen(tls: true, auth: nil)
    }
    
    @discardableResult
    func listen(tls: Bool) throws -> URLEndpointListener {
        return try! listen(tls: tls, auth: nil)
    }
    
    @discardableResult
    func listen(tls: Bool, auth: ListenerAuthenticator?) throws -> URLEndpointListener {
        // Stop:
        if let listener = self.listener {
            listener.stop()
        }
        
        // Listener:
        let config = URLEndpointListenerConfiguration.init(database: self.oDB)
        config.port = tls ? wssPort : wsPort
        config.disableTLS = !tls
        config.authenticator = auth
        self.listener = URLEndpointListener.init(config: config)
        
        // Start:
        try self.listener!.start()
        
        return self.listener!
    }
    
    func stopListen() throws {
        if let listener = self.listener {
            try stopListener(listener: listener)
        }
    }
    
    func stopListener(listener: URLEndpointListener) throws {
        let identity = listener.tlsIdentity
        listener.stop()
        if let id = identity {
            try id.deleteFromKeyChain()
        }
    }
    
    override func tearDown() {
        try! stopListen()
        super.tearDown()
    }
    
    func testTLSIdentity() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        // Disabled TLS:
        var config = URLEndpointListenerConfiguration.init(database: self.oDB)
        config.disableTLS = true
        var listener = URLEndpointListener.init(config: config)
        XCTAssertNil(listener.tlsIdentity)
        
        try listener.start()
        XCTAssertNil(listener.tlsIdentity)
        try stopListener(listener: listener)
        XCTAssertNil(listener.tlsIdentity)
        
        // Anonymous Identity:
        config = URLEndpointListenerConfiguration.init(database: self.oDB)
        listener = URLEndpointListener.init(config: config)
        XCTAssertNil(listener.tlsIdentity)
        
        try listener.start()
        XCTAssertNotNil(listener.tlsIdentity)
        try stopListener(listener: listener)
        XCTAssertNil(listener.tlsIdentity)
        
        // User Identity:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel);
        let attrs = [certAttrCommonName: "CBL-Server"]
        let identity = try TLSIdentity.createIdentity(forServer: true,
                                                      attributes: attrs,
                                                      expiration: nil,
                                                      label: serverCertLabel)
        config = URLEndpointListenerConfiguration.init(database: self.oDB)
        config.tlsIdentity = identity
        listener = URLEndpointListener.init(config: config)
        XCTAssertNil(listener.tlsIdentity)
        
        try listener.start()
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssert(identity === listener.tlsIdentity!)
        try stopListener(listener: listener)
        XCTAssertNil(listener.tlsIdentity)
    }
    
    func testPasswordAuthenticator() throws {
        // Listener:
        let listenerAuth = ListenerPasswordAuthenticator.init {
            (username, password) -> Bool in
            return (username as NSString).isEqual(to: "daniel") &&
                   (password as NSString).isEqual(to: "123")
        }
        let listener = try listen(tls: false, auth: listenerAuth)
        
        // Replicator - No Authenticator:
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: nil, expectedError: CBLErrorHTTPAuthRequired)
        
        // Replicator - Wrong Credentials:
        var auth = BasicAuthenticator.init(username: "daniel", password: "456")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: auth, expectedError: CBLErrorHTTPAuthRequired)
        
        // Replicator - Success:
        auth = BasicAuthenticator.init(username: "daniel", password: "123")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: auth)
        
        // Cleanup:
        try stopListen()
    }
    
    func testClientCertAuthenticatorWithClosure() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init { (certs) -> Bool in
            XCTAssertEqual(certs.count, 1)
            var commongName: CFString?
            let status = SecCertificateCopyCommonName(certs[0], &commongName)
            XCTAssertEqual(status, errSecSuccess)
            XCTAssertNotNil(commongName)
            XCTAssertEqual((commongName! as String), "daniel")
            return true
        }
        let listener = try listen(tls: true, auth: listenerAuth)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        
        // Create client identity:
        let attrs = [certAttrCommonName: "daniel"]
        let identity = try TLSIdentity.createIdentity(forServer: false, attributes: attrs, expiration: nil, label: clientCertLabel)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator.init(identity: identity)
        let serverCert = listener.tlsIdentity!.certs[0]
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth, serverCert: serverCert)
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        try stopListen()
    }
    
    func testClientCertAuthenticatorWithRootCerts() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        // Root Cert:
        let rootCertData = try dataFromResource(name: "identity/client-ca", ofType: "der")
        let rootCert = SecCertificateCreateWithData(kCFAllocatorDefault, rootCertData as CFData)!
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init(rootCerts: [rootCert])
        let listener = try listen(tls: true, auth: listenerAuth)
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        
        // Create client identity:
        let clientCertData = try dataFromResource(name: "identity/client", ofType: "p12")
        let identity = try TLSIdentity.importIdentity(withData: clientCertData, password: "123", label: clientCertLabel)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator.init(identity: identity)
        let serverCert = listener.tlsIdentity!.certs[0]
        
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth, serverCert: serverCert)
        }
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        try stopListen()
    }
    
    func testServerCertVerificationModeSelfSignedCert() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        // Listener:
        let listener = try listen(tls: true)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator - TLS Error:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     serverCertVerifyMode: .caCert, serverCert: nil, expectedError: CBLErrorTLSCertUnknownRoot)
        }
        
        // Replicator - Success:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     serverCertVerifyMode: .selfSignedCert, serverCert: nil)
        }
        
        // Cleanup
        try stopListen()
    }
    
    func testServerCertVerificationModeCACert() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        // Listener:
        let listener = try listen(tls: true)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator - TLS Error:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     serverCertVerifyMode: .caCert, serverCert: nil, expectedError: CBLErrorTLSCertUnknownRoot)
        }
        
        // Replicator - Success:
        self.ignoreException {
            let serverCert = listener.tlsIdentity!.certs[0]
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     serverCertVerifyMode: .caCert, serverCert: serverCert)
        }
        
        // Cleanup
        try stopListen()
    }
    
    func testPort() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.port = wsPort
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.port)
        
        // Start:
        try self.listener!.start()
        XCTAssertEqual(self.listener!.port, wsPort)

        try stopListen()
        XCTAssertNil(self.listener!.port)
    }
    
    func testEmptyPort() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.port)
        
        // Start:
        try self.listener!.start()
        XCTAssertNotEqual(self.listener!.port, 0)

        try stopListen()
        XCTAssertNil(self.listener!.port)
    }
    
    func testBusyPort() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        try listen()
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.port = self.listener!.port
        let listener2 = URLEndpointListener(config: config)
        
        expectError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE)) {
            try listener2.start()
        }
    }
    
    func testURLs() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.port = wsPort
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.urls)
        
        // Start:
        try self.listener!.start()
        XCTAssert(self.listener!.urls?.count != 0)

        try stopListen()
        XCTAssertNil(self.listener!.urls)
    }
    
    func testConnectionStatus() throws {
        if !self.keyChainAccessAllowed {
            return
        }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.port = wsPort
        config.disableTLS = true
        self.listener = URLEndpointListener(config: config)
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
        
        // Start:
        try self.listener!.start()
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
        
        try generateDocument(withID: "doc-1")
        let rConfig = self.config(target: self.listener!.localURLEndpoint,
                                 type: .pushAndPull, continuous: false, auth: nil,
                                 serverCertVerifyMode: .caCert, serverCert: nil)
        var maxConnectionCount: UInt64 = 0, maxActiveCount:UInt64 = 0
        run(config: rConfig, reset: false, expectedError: nil) { (replicator) in
            replicator.addChangeListener { (change) in
                maxConnectionCount = max(self.listener!.status.connectionCount, maxConnectionCount)
                maxActiveCount = max(self.listener!.status.activeConnectionCount, maxActiveCount)
            }
        }
        XCTAssertEqual(maxConnectionCount, 1)
        XCTAssertEqual(maxActiveCount, 1)
        XCTAssertEqual(self.oDB.count, 1)

        try stopListen()
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
    }
    
}

@available(macOS 10.12, iOS 10.0, *)
extension URLEndpointListener {
    var localURL: URL {
        assert(self.port != nil && self.port! > UInt16(0))
        var comps = URLComponents()
        comps.scheme = self.config.disableTLS ? "ws" : "wss"
        comps.host = "localhost"
        comps.port = Int(self.port!)
        comps.path = "/\(self.config.database.name)"
        return comps.url!
    }
    
    var localURLEndpoint: URLEndpoint {
        return URLEndpoint.init(url: self.localURL)
    }
}
