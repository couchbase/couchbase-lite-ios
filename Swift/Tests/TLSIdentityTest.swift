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

class TLSIdentityTest: CBLTestCase {
    let serverCertLabel = "CBL-Swift-Server-Cert"
    let clientCertLabel = "CBL-Swift-Client-Cert"
    let caCertLabel = "CBL-Swift-CA-Cert"
    let serverCertAttrs = [certAttrCommonName: "CBL-Server"]
    let clientCertAttrs = [certAttrCommonName: "CBL-Server"]
    
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
        let publicKey = SecTrustCopyKey(trust!)
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
    }
    
    func store(privateKey: SecKey, certs: [SecCertificate], label: String) {
        XCTAssert(certs.count > 0)
        
        // Private Key:
        store(privateKey: privateKey)
        
        // Certs:
        var i = 0;
        for cert in certs {
            store(cert: cert, label: (i == 0 ? label : "com.couchbase.lite.cert"))
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
    
    func delete(cert: SecCertificate) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert
        ]

        let status = SecItemDelete(query as CFDictionary)
        XCTAssert(status == errSecSuccess || status == errSecItemNotFound || status == errSecInvalidItemRef)
    }
    
    func delete(key: SecKey) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecValueRef: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        XCTAssert(status == errSecSuccess || status == errSecItemNotFound || status == errSecInvalidItemRef)
    }
    
    override func setUp() {
        super.setUp()
        if (!keyChainAccessAllowed) { return }
        
        ignoreException {
            try? TLSIdentity.deleteIdentity(withLabel: self.serverCertLabel)
        }
        ignoreException {
            try? TLSIdentity.deleteIdentity(withLabel: self.clientCertLabel)
        }
        ignoreException {
            try? TLSIdentity.deleteIdentity(withLabel: self.caCertLabel)
        }
    }
    
    override func tearDown() {
        super.tearDown()
        if (!keyChainAccessAllowed) { return }
        
        ignoreException {
            try? TLSIdentity.deleteIdentity(withLabel: self.serverCertLabel)
        }
        ignoreException {
            try? TLSIdentity.deleteIdentity(withLabel: self.clientCertLabel)
        }
        ignoreException {
            try? TLSIdentity.deleteIdentity(withLabel: self.caCertLabel)
        }
    }
    
    func testCreateGetDeleteServerIdentity() throws {
        try XCTSkipUnless(keyChainAccessAllowed)
        
        // Get:
        var identity: TLSIdentity?
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            identity = try TLSIdentity.identity(withLabel: self.serverCertLabel)
        }
        
        // Create:
        identity = try TLSIdentity.createIdentity(for: .serverAuth,
                                                  attributes: serverCertAttrs,
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
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            identity = try TLSIdentity.identity(withLabel: self.serverCertLabel)
        }
    }
    
    func testCreateDuplicateServerIdentity() throws {
        try XCTSkipUnless(keyChainAccessAllowed)
        
        // Create:
        var identity: TLSIdentity?
        identity = try TLSIdentity.createIdentity(for: .serverAuth,
                                                  attributes: serverCertAttrs,
                                                  label: serverCertLabel)
        XCTAssertNotNil(identity)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        
        // Create again with the same label:
        self.expectError(domain: CBLError.domain, code: CBLError.crypto) {
            identity = try TLSIdentity.createIdentity(for: .serverAuth,
                                                      attributes: self.serverCertAttrs,
                                                      label: self.serverCertLabel)
        }
    }
    
    func testCreateGetDeleteClientIdentity() throws {
        try XCTSkipUnless(keyChainAccessAllowed)
        
        // Get:
        var identity: TLSIdentity?
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            identity = try TLSIdentity.identity(withLabel: self.clientCertLabel)
        }
        
        // Create:
        identity = try TLSIdentity.createIdentity(for: .clientAuth,
                                                  attributes: clientCertAttrs,
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
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            identity = try TLSIdentity.identity(withLabel: self.clientCertLabel)
        }
    }
    
    func testCreateDuplicateClientIdentity() throws {
        try XCTSkipUnless(keyChainAccessAllowed)
        
        // Create:
        var identity: TLSIdentity?
        identity = try TLSIdentity.createIdentity(for: .clientAuth,
                                                  attributes: clientCertAttrs,
                                                  label: clientCertLabel)
        XCTAssertNotNil(identity)
        
        // Get:
        identity = try TLSIdentity.identity(withLabel: clientCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        
        // Create again with the same label:
        self.expectError(domain: CBLError.domain, code: CBLError.crypto) {
            identity = try TLSIdentity.createIdentity(for: .clientAuth,
                                                      attributes: self.clientCertAttrs,
                                                      label: self.clientCertLabel)
        }
    }
    
    func testGetIdentityWithIdentity() throws {
        try XCTSkipUnless(keyChainAccessAllowed)
        
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
        
        // For iOS, need to explicitly store the identity into the KeyChain as SecPKCS12Import doesn't do it.
        #if os(iOS)
            for cert in certs {
                delete(cert: cert);
            }
            delete(key: privateKey!);
            store(privateKey: privateKey!, certs: certs, label: serverCertLabel)
        #endif
        
        // Get identity:
        let identity = try TLSIdentity.identity(withIdentity: secIdentity, certs: [certs[1]])
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity.certs.count, 2)
        
        // Clean up for macOS:
        #if os(macOS)
        for cert in certs {
            delete(cert: cert);
        }
        delete(key: privateKey!);
        #endif
    }
    
    func testImportIdentity() throws {
        #if os(macOS)
        try XCTSkipIf(true, "CBL-7005 : importIdentityWithData not working on newer macOS")
        #endif
        
        try XCTSkipUnless(keyChainAccessAllowed)
        
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
        ignoreException {
            try TLSIdentity.deleteIdentity(withLabel: self.serverCertLabel)
        }
        
        // Get:
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            identity = try TLSIdentity.identity(withLabel: self.serverCertLabel)
        }
    }
    
    func testCreateIdentityWithNoAttributes() throws {
        try XCTSkipUnless(keyChainAccessAllowed)
        
        // Get:
        var identity: TLSIdentity?
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            identity = try TLSIdentity.identity(withLabel: self.serverCertLabel)
        }
        
        XCTAssertNil(identity)
        
        // Create:
        self.expectError(domain: CBLError.domain, code: CBLError.crypto) {
            identity = try TLSIdentity.createIdentity(for: .clientAuth,
                                                      attributes: [:],
                                                      label: self.clientCertLabel)
        }
    }
    
    func testCertificateExpiration() throws {
        try XCTSkipUnless(keyChainAccessAllowed)
        
        // Get:
        var identity: TLSIdentity?
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            identity = try TLSIdentity.identity(withLabel: self.serverCertLabel)
        }
        
        let attrs = [certAttrCommonName: "CBL-Server"]
        let expiration = Date(timeIntervalSinceNow: 300)
        identity = try TLSIdentity.createIdentity(for: .serverAuth,
                                                  attributes: attrs,
                                                  expiration: expiration,
                                                  label: serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity!.certs.count, 1)
        
        // The actual expiration will be slightly less than the set expiration time:
        XCTAssert(abs(expiration.timeIntervalSince1970 - identity!.expiration.timeIntervalSince1970) < 5.0)
    }
    
    func testCreateIdentitySignedWithIssuer() throws {
        try XCTSkipUnless(keyChainAccessAllowed)
        
        let caKeyData = try dataFromResource(name: "identity/ca-key", ofType: "der")
        let caCertData = try dataFromResource(name: "identity/ca-cert", ofType: "der")
        
        let issuer = try TLSIdentity.createIdentity(withPrivateKey: caKeyData,
                                                    certificate: caCertData)
        
        let identity = try TLSIdentity.createIdentity(for: .serverAuth,
                                                      attributes: serverCertAttrs,
                                                      issuer: issuer,
                                                      label: serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity.certs.count, 2)
        checkIdentityInKeyChain(identity: identity)
        
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        var status = SecTrustCreateWithCertificates(identity.certs[0], policy, &trust)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(trust)
 
        // Validate if the identity is signed by the ca cert using trust check:
        status = SecTrustSetAnchorCertificates(trust!, issuer.certs as CFArray)
        XCTAssertEqual(status, errSecSuccess)
        
        SecTrustSetAnchorCertificatesOnly(trust!, true)
        
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust!, &error)
        XCTAssertTrue(isValid)
        
        // Check the identity in KeyChain:
        let checkIdentity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNotNil(checkIdentity)
        XCTAssertEqual(checkIdentity?.certs.count, 2)
        
        // Delete the identity which is a cert chain:
        try TLSIdentity.deleteIdentity(withLabel: self.serverCertLabel)
        
        // Check the identity in KeyChain:
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            _ = try TLSIdentity.identity(withLabel: self.serverCertLabel)
        }
    }
    
    func testCreateIdentitySignedWithImportedIssuer() throws {
        #if os(macOS)
        try XCTSkipIf(true, "CBL-7005 : importIdentityWithData not working on newer macOS")
        #endif
        
        try XCTSkipUnless(keyChainAccessAllowed)
        
        let data = try dataFromResource(name: "identity/ca", ofType: "p12")
        
        let issuer = try TLSIdentity.importIdentity(withData: data,
                                                    password: "123",
                                                    label: self.caCertLabel)
        
        let identity = try TLSIdentity.createIdentity(for: .serverAuth,
                                                      attributes: serverCertAttrs,
                                                      issuer: issuer,
                                                      label: self.serverCertLabel)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity.certs.count, 2)
        checkIdentityInKeyChain(identity: identity)
        
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        var status = SecTrustCreateWithCertificates(identity.certs[0], policy, &trust)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(trust)
 
        // Validate if the identity is signed by the ca cert using trust check:
        status = SecTrustSetAnchorCertificates(trust!, issuer.certs as CFArray)
        XCTAssertEqual(status, errSecSuccess)
        
        SecTrustSetAnchorCertificatesOnly(trust!, true)
        
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust!, &error)
        XCTAssertTrue(isValid)
        
        // Check the identity in KeyChain:
        let checkIdentity = try TLSIdentity.identity(withLabel: serverCertLabel)
        XCTAssertNotNil(checkIdentity)
        XCTAssertEqual(checkIdentity?.certs.count, 2)
        
        // Delete the identity which is a cert chain:
        try TLSIdentity.deleteIdentity(withLabel: self.serverCertLabel)
        
        // Check the identity in KeyChain:
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            _ = try TLSIdentity.identity(withLabel: self.serverCertLabel)
        }
    }
}
