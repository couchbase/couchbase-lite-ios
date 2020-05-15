//
//  TLSIdentityTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc. All rights reserved.
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
import CouchbaseLiteSwift

@available(macOS 10.12, iOS 10.0, *)
class TLSIdentityTest: CBLTestCase {
    let serverCertLabel = "CBL-Swift-Server-Cert"
    let clientCertLabel = "CBL-Swift-Client-Cert"
    
    func findInKeyChain(params: [String: Any]) -> CFTypeRef? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(params as CFDictionary, &result)
        if status != errSecSuccess {
            if status == errSecItemNotFound {
                return nil
            } else {
                print("Couldn't get an item from the Keychain: \(params) (error: \(status)")
            }
        }
        XCTAssert(result != nil)
        return result
    }
    
    func publicKeyHashFromCert(cert: SecCertificate) -> Data {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(trust)
        let publicKey = SecTrustCopyPublicKey(trust!)
        XCTAssertNotNil(publicKey)
        let attrs = SecKeyCopyAttributes(publicKey!) as! [String: Any]
        let hash = attrs[String(kSecAttrApplicationLabel)] as! Data
        return hash
    }
    
    func checkIdentityInKeyChain(identity: TLSIdentity) {
        // Cert:
        let certs = identity.certs
        XCTAssert(certs.count > 0)
        let cert = certs[0]
        
        // Private Key:
        let publicKeyHash = publicKeyHashFromCert(cert: cert)
        let privateKey = findInKeyChain(params: [
            String(kSecClass):                  kSecClassKey,
            String(kSecAttrKeyType):            kSecAttrKeyTypeRSA,
            String(kSecAttrKeyClass):           kSecAttrKeyClassPrivate,
            String(kSecAttrApplicationLabel):   publicKeyHash,
            String(kSecReturnRef):              true
        ]) as! SecKey?
        XCTAssertNotNil(privateKey)
        
        // Get public key from cert via trust:
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(trust)
        let publicKey = SecTrustCopyPublicKey(trust!)
        XCTAssertNotNil(publicKey)
        
        // Check public key data:
        var error: Unmanaged<CFError>?
        let data = SecKeyCopyExternalRepresentation(publicKey!, &error) as Data?
        XCTAssertNil(error)
        XCTAssertNotNil(data)
        XCTAssert(data!.count > 0)
    }
    
    override func setUp() {
        super.setUp()
        try! TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        try! TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
    }
    
    override func tearDown() {
        super.tearDown()
        try! TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        try! TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
    }
    
    func testCreateGetDeleteServerIdentity() throws {
        if (!isHostApp) { return }
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        
        // Get:
        var identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNil(identity)
        
        // Create:
        let attrs = [certAttrCommonName: "CBL-Server"]
        identity = try TLSIdentity.createIdentity(forServer: true,
                                                  attributes: attrs,
                                                  expiration: nil,
                                                  label: serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        checkIdentityInKeyChain(identity: identity!)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        checkIdentityInKeyChain(identity: identity!)
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNil(identity)
    }
    
    func testCreateDuplicateServerIdentity() throws {
        if (!isHostApp) { return }
        
        // Create:
        var identity: TLSIdentity?
        let attrs = [certAttrCommonName: "CBL-Server"]
        identity = try TLSIdentity.createIdentity(forServer: true,
                                                  attributes: attrs,
                                                  expiration: nil,
                                                  label: serverCertLabel)
        XCTAssertNotNil(identity)
        checkIdentityInKeyChain(identity: identity!)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        checkIdentityInKeyChain(identity: identity!)
        
        // Create again with the same label:
        self.expectError(domain: CBLErrorDomain, code: CBLErrorCrypto) {
            identity = try TLSIdentity.createIdentity(forServer: true,
                                                      attributes: attrs,
                                                      expiration: nil,
                                                      label: self.serverCertLabel)
        }
    }
    
    func testCreateGetDeleteClientIdentity() throws {
        if (!isHostApp) { return }
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        
        // Get:
        var identity = try TLSIdentity.identity(withLabel: clientCertLabel)
        XCTAssertNil(identity)
        
        // Create:
        let attrs = [certAttrCommonName: "CBL-Client"]
        identity = try TLSIdentity.createIdentity(forServer: false,
                                                  attributes: attrs,
                                                  expiration: nil,
                                                  label: clientCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        checkIdentityInKeyChain(identity: identity!)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: clientCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        checkIdentityInKeyChain(identity: identity!)
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: clientCertLabel)
        XCTAssertNil(identity)
    }
    
    func testCreateDuplicateClientIdentity() throws {
        if (!isHostApp) { return }
        
        // Create:
        var identity: TLSIdentity?
        let attrs = [certAttrCommonName: "CBL-Client"]
        identity = try TLSIdentity.createIdentity(forServer: false,
                                                  attributes: attrs,
                                                  expiration: nil,
                                                  label: clientCertLabel)
        XCTAssertNotNil(identity)
        checkIdentityInKeyChain(identity: identity!)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: clientCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        checkIdentityInKeyChain(identity: identity!)
        
        // Create again with the same label:
        self.expectError(domain: CBLErrorDomain, code: CBLErrorCrypto) {
            identity = try TLSIdentity.createIdentity(forServer: false,
                                                      attributes: attrs,
                                                      expiration: nil,
                                                      label: self.clientCertLabel)
        }
    }
    
    func testCreateIdentityWithNoAttributes() throws {
        if (!isHostApp) { return }
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        
        // Get:
        var identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNil(identity)
        
        // Create:
        self.expectError(domain: CBLErrorDomain, code: CBLErrorCrypto) {
            identity = try TLSIdentity.createIdentity(forServer: false,
                                                      attributes: [:],
                                                      expiration: nil,
                                                      label: self.clientCertLabel)
        }
    }
    
    func testCertificateExpiration() throws {
        if (!isHostApp) { return }
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        
        // Get:
        var identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNil(identity)
        
        let expiration = Date.init(timeIntervalSinceNow: 300)
        let attrs = [certAttrCommonName: "CBL-Server"]
        identity = try TLSIdentity.createIdentity(forServer: true,
                                                  attributes: attrs,
                                                  expiration: expiration,
                                                  label: serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        checkIdentityInKeyChain(identity: identity!)
        
        // The actual expiration will be slightly less than the set expiration time:
        XCTAssert(abs(expiration.timeIntervalSince1970 - identity!.expiration.timeIntervalSince1970) < 5.0)
    }
}
