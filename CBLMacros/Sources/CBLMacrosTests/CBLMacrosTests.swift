//
//  CBLMacrosTests.swift
//  CBLMacros
//
//  Created by Callum Birks on 27/02/2025.
//

import CBLMacrosMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Test func testExpansion() {
    assertMacroExpansion("""
    @DocumentModel
    class Person {
        @DocumentId var id: String?
        var name: String
        let age: Int
    }
    """, expandedSource: """
    class Person {
        @DocumentId var id: String?
        var name: String
        let age: Int
    }
    
    extension Person: DocumentObject {
        var __ref: DocumentId {
            return $id
        }
    }
    """, macroSpecs: ["DocumentModel": DocumentMacro.spec], failureHandler: { Issue.record("\($0.message)") })
}
