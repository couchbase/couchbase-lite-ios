//
//  TLSIdentityTest.swift
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
import CouchbaseLiteSwift

@available(macOS 10.12, iOS 10.3, *)
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
    
    func store(privateKey: SecKey, certs: [SecCertificate], label: String) {
        XCTAssert(certs.count > 0)
        
        // Private Key:
        store(privateKey: privateKey)
        
        // Certs:
        var i = 0;
        for cert in certs {
            store(cert: cert, label: (i == 0 ? label : nil))
            i = i + 1
        }
    }
    
    func store(privateKey: SecKey) {
        let params: [String : Any] = [
            String(kSecClass):          kSecClassKey,
            String(kSecAttrKeyType):    kSecAttrKeyTypeRSA,
            String(kSecAttrKeyClass):   kSecAttrKeyClassPrivate,
            String(kSecValueRef):       privateKey
        ]
        let status = SecItemAdd(params as CFDictionary, nil)
        XCTAssertEqual(status, errSecSuccess)
    }
    
    func store(cert: SecCertificate, label: String?) {
        var params: [String : Any] = [
            String(kSecClass):          kSecClassCertificate,
            String(kSecValueRef):       cert
        ]
        if let l = label {
            params[String(kSecAttrLabel)] = l
        }
        let status = SecItemAdd(params as CFDictionary, nil)
        XCTAssertEqual(status, errSecSuccess)
    }
    
    func update(cert: SecCertificate, label: String) {
        let query: [String : Any] = [
            String(kSecClass):          kSecClassCertificate,
            String(kSecValueRef):       cert
        ]
        
        let update: [String: Any] = [
            String(kSecClass):          kSecClassCertificate,
            String(kSecValueRef):       cert,
            String(kSecAttrLabel):      label
        ]
        
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        XCTAssertEqual(status, errSecSuccess)
    }
    
    override func setUp() {
        super.setUp()
        if (!keyChainAccessAllowed) { return }
        
        try! TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        try! TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
    }
    
    override func tearDown() {
        super.tearDown()
        if (!keyChainAccessAllowed) { return }
        
        try! TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        try! TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
    }
    
    func testCreateGetDeleteServerIdentity() throws {
        if (!keyChainAccessAllowed) { return }
        
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
        if (!keyChainAccessAllowed) { return }
        
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
        if (!keyChainAccessAllowed) { return }
        
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
        if (!keyChainAccessAllowed) { return }
        
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
    
    func testGetIdentityWithIdentity() throws {
        if (!keyChainAccessAllowed) { return }
        
        // Use SecPKCS12Import to import the PKCS12 data:
        var result : CFArray?
        var status = errSecSuccess
        let data = try dataFromResource(name: "identity/certs", ofType: "p12")
        let options = [String(kSecImportExportPassphrase): "123"]
        ignoreException {
            status = SecPKCS12Import(data as CFData, options as CFDictionary, &result)
        }
        XCTAssertEqual(status, errSecSuccess)
        
        // Identity:
        let importedItems = result! as NSArray
        XCTAssert(importedItems.count > 0)
        let item = importedItems[0] as! [String: Any]
        let secIdentity = item[String(kSecImportItemIdentity)] as! SecIdentity
        
        // Private Key:
        var privateKey : SecKey?
        status = SecIdentityCopyPrivateKey(secIdentity, &privateKey)
        XCTAssertEqual(status, errSecSuccess)
        
        // Certs:
        let certs = item[String(kSecImportItemCertChain)] as! [SecCertificate]
        XCTAssertEqual(certs.count, 2)
        
        // For iOS, need to save the identity into the KeyChain.
        // Save or Update identity with a label so that it could be cleaned up easily:
        #if os(iOS)
            store(privateKey: privateKey!, certs: certs, label: serverCertLabel)
        #else
            update(cert: certs[0] as SecCertificate, label: serverCertLabel)
        #endif
        
        // Get identity:
        let identity = try TLSIdentity.identity(withIdentity: secIdentity, certs: [certs[1]])
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity.certs.count, 2)
        
        // Delete from KeyChain:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
    }
    
    func testImportIdentity() throws {
        if (!keyChainAccessAllowed) { return }
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        
        let data = try dataFromResource(name: "identity/certs", ofType: "p12")
        
        var identity: TLSIdentity?
        // When importing P12 file on macOS unit test, there is an internal exception thrown
        // inside SecPKCS12Import() which doesn't actually cause anything. Ignore the exception
        // so that the exception breakpoint will not be triggered.
        ignoreException {
            identity = try TLSIdentity.importIdentity(withData: data,
                                                      password: "123",
                                                      label: self.serverCertLabel)
        }
        
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 2)
        checkIdentityInKeyChain(identity: identity!)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 2)
        checkIdentityInKeyChain(identity: identity!)
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNil(identity)
    }
    
    func testCreateIdentityWithNoAttributes() throws {
        if (!keyChainAccessAllowed) { return }
        
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
        if (!keyChainAccessAllowed) { return }
        
        // Delete:
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        
        // Get:
        var identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNil(identity)
        
        let attrs = [certAttrCommonName: "CBL-Server"]
        let expiration = Date(timeIntervalSinceNow: 300)
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
