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
        
        return try listen(config: config)
    }
    
    @discardableResult
    func listen(config: URLEndpointListenerConfiguration) throws -> URLEndpointListener {
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
    
    func cleanUpIdentities() throws {
        try URLEndpointListener.deleteAnonymousIdentities()
    }
    
    func replicator(db: Database, continuous: Bool, target: Endpoint, serverCert: SecCertificate?) -> Replicator {
        let config = ReplicatorConfiguration(database: db, target: target)
        config.replicatorType = .pushAndPull
        config.continuous = continuous
        config.pinnedServerCertificate = serverCert
        return Replicator(config: config)
    }
    
    /// Two replicators, replicates docs to the self.listener; validates connection status
    func validateMultipleReplicationsTo() throws {
        let exp1 = expectation(description: "replicator#1 stop")
        let exp2 = expectation(description: "replicator#2 stop")
        let count = self.listener!.config.database.count
        
        // open DBs
        try deleteDB(name: "db1")
        try deleteDB(name: "db2")
        let db1 = try openDB(name: "db1")
        let db2 = try openDB(name: "db2")
        
        // For keeping the replication long enough to validate connection status, we will use blob
        let imageData = try dataFromResource(name: "image", ofType: "jpg")
        
        // DB#1
        let doc1 = createDocument()
        let blob1 = Blob(contentType: "image/jpg", data: imageData)
        doc1.setBlob(blob1, forKey: "blob")
        try db1.saveDocument(doc1)
        
        // DB#2
        let doc2 = createDocument()
        let blob2 = Blob(contentType: "image/jpg", data: imageData)
        doc2.setBlob(blob2, forKey: "blob")
        try db2.saveDocument(doc2)
        
        let repl1 = replicator(db: db1,
                               continuous: false,
                               target: self.listener!.localURLEndpoint,
                               serverCert: self.listener!.tlsIdentity!.certs[0])
        let repl2 = replicator(db: db2,
                               continuous: false,
                               target: self.listener!.localURLEndpoint,
                               serverCert: self.listener!.tlsIdentity!.certs[0])
        
        var maxConnectionCount: UInt64 = 0, maxActiveCount: UInt64 = 0
        let changeListener = { (change: ReplicatorChange) in
            if change.status.activity == .busy {
                maxConnectionCount = max(self.listener!.status.connectionCount, maxConnectionCount);
                maxActiveCount = max(self.listener!.status.activeConnectionCount, maxActiveCount);
            }
            
            if change.status.activity == .stopped {
                if change.replicator.config.database.name == "db1" {
                    exp1.fulfill()
                } else {
                    exp2.fulfill()
                }
            }
            
        }
        let token1 = repl1.addChangeListener(changeListener)
        let token2 = repl2.addChangeListener(changeListener)
        
        repl1.start()
        repl2.start()
        wait(for: [exp1, exp2], timeout: 5.0)
        
        // check both replicators access listener at same time
        XCTAssertEqual(maxConnectionCount, 2);
        XCTAssertEqual(maxActiveCount, 2);
        
        // all data are transferred to/from
        XCTAssertEqual(self.listener!.config.database.count, count + 2);
        XCTAssertEqual(db1.count, count + 1/* db2 doc*/);
        XCTAssertEqual(db2.count, count + 1/* db1 doc*/);
        
        repl1.removeChangeListener(withToken: token1)
        repl2.removeChangeListener(withToken: token2)
        
        try db1.close()
        try db2.close()
    }
    
    override func setUp() {
        super.setUp()
        try! cleanUpIdentities()
    }
    
    override func tearDown() {
        try! stopListen()
        try! cleanUpIdentities()
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
    
    func testMultipleListenersOnSameDatabase() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        let listener1 = URLEndpointListener(config: config)
        let listener2 = URLEndpointListener(config: config)
        
        try listener1.start()
        try listener2.start()
        
        try generateDocument(withID: "doc-1")
        self.run(target: listener1.localURLEndpoint,
                 type: .pushAndPull,
                 continuous: false,
                 auth: nil,
                 serverCert: listener1.tlsIdentity!.certs[0])
        
        // since listener1 and listener2 are using same certificates, one listener only needs stop.
        listener2.stop()
        try stopListener(listener: listener1)
        XCTAssertEqual(self.oDB.count, 1)
    }
    
    func testReplicatorAndListenerOnSameDatabase() throws {
        if !self.keyChainAccessAllowed { return }
        
        let exp1 = expectation(description: "replicator#1 stop")
        let exp2 = expectation(description: "replicator#2 stop")
        
        // listener
        let doc = createDocument()
        try self.oDB.saveDocument(doc)
        try listen()
        
        // Replicator#1 (otherDB -> DB#1)
        let doc1 = createDocument()
        try self.db.saveDocument(doc1)
        let target = DatabaseEndpoint(database: self.db)
        let repl1 = replicator(db: self.oDB, continuous: true, target: target, serverCert: nil)
        
        // Replicator#2 (DB#2 -> Listener(otherDB))
        try deleteDB(name: "db2")
        let db2 = try openDB(name: "db2")
        let doc2 = createDocument()
        try db2.saveDocument(doc2)
        let repl2 = replicator(db: db2,
                               continuous: true,
                               target: self.listener!.localURLEndpoint,
                               serverCert: self.listener!.tlsIdentity!.certs[0])
        
        let changeListener = { (change: ReplicatorChange) in
            if change.status.activity == .idle &&
                change.status.progress.completed == change.status.progress.total {
                if self.oDB.count == 3 && self.db.count == 3 && db2.count == 3 {
                    change.replicator.stop()
                }
            }
            
            if change.status.activity == .stopped {
                if change.replicator.config.database.name == "db2" {
                    exp2.fulfill()
                } else {
                    exp1.fulfill()
                }
            }
            
        }
        let token1 = repl1.addChangeListener(changeListener)
        let token2 = repl2.addChangeListener(changeListener)
        
        repl1.start()
        repl2.start()
        wait(for: [exp1, exp2], timeout: 5.0)
        
        XCTAssertEqual(self.oDB.count, 3)
        XCTAssertEqual(self.db.count, 3)
        XCTAssertEqual(db2.count, 3)
        
        repl1.removeChangeListener(withToken: token1)
        repl2.removeChangeListener(withToken: token2)
        
        try db2.close()
        try stopListen()
    }
    
    func testCloseWithActiveListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        try listen()
        
        // Close database should also stop the listener:
        try self.oDB.close()
        
        XCTAssertNil(self.listener!.port)
        XCTAssertNil(self.listener!.urls)
        
        try stopListen()
    }
    
    // TODO: https://issues.couchbase.com/browse/CBL-1008
    func _testEmptyNetworkInterface() throws {
        if !self.keyChainAccessAllowed { return }
        
        try listen()
        
        for (i, url) in self.listener!.urls!.enumerated() {
            // separate db instance!
            let db = try Database(name: "db-\(i)")
            let doc = createDocument()
            doc.setString(url.absoluteString, forKey: "url")
            try db.saveDocument(doc)
            
            // separate replicator instance
            let target = URLEndpoint(url: url)
            let rConfig = ReplicatorConfiguration(database: db, target: target)
            rConfig.pinnedServerCertificate = self.listener?.tlsIdentity!.certs[0]
            run(config: rConfig, expectedError: nil)
            
            // remove the db
            try db.delete()
        }
        
        XCTAssertEqual(self.oDB.count, UInt64(self.listener!.urls!.count))
        
        let q = QueryBuilder.select([SelectResult.all()]).from(DataSource.database(self.oDB))
        let rs = try q.execute()
        var result = [URL]()
        for res in rs.allResults() {
            let dict = res.dictionary(at: 0)
            result.append(URL(string: dict!.string(forKey: "url")!)!)
        }
        
        XCTAssertEqual(result, self.listener!.urls)
        try stopListen()
        
        // validate 0.0.0.0 meta-address should return same empty response.
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.networkInterface = "0.0.0.0"
        try listen(config: config)
        XCTAssertEqual(self.listener!.urls!, result)
        try stopListen()
    }
    
    func testMultipleReplicatorsToListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        try listen()
        
        let doc = createDocument()
        doc.setString("Tiger", forKey: "species")
        try self.oDB.saveDocument(doc)
        
        try validateMultipleReplicationsTo()
        
        try stopListen()
    }
    
    // TODO: https://issues.couchbase.com/browse/CBL-954
    func _testReadOnlyListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.readOnly = true
        try listen(config: config)
        
        self.run(target: self.listener!.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: nil, serverCert: self.listener!.tlsIdentity!.certs[0],
                 expectedError: CBLErrorHTTPForbidden)
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
