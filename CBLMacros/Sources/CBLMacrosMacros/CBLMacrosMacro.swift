import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros

public struct DocumentMacro: ExtensionMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(ClassDeclSyntax.self)
        else {
            throw DocumentMacroError.onlyApplicableToStruct
        }
        
        let variables = structDecl.memberBlock.members.compactMap { structMember in
            structMember.decl.as(VariableDeclSyntax.self)
        }
        
        // Locate an @DocumentId field
        guard let docRef = (variables.first { $0.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "DocumentId" }) }) else {
            throw DocumentMacroError.missingDocumentId
        }
        
        // Get the name of the field
        guard let docRefId = docRef.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            throw DocumentMacroError.parseDocumentIdFailed
        }

        let ext = try ExtensionDeclSyntax("""
        extension \(raw: structDecl.name.text): DocumentObject {
            var __ref: DocumentId {
                return $\(raw: docRefId)
            }
        }
        """)

        return [
            ext
        ]
    }

    public static var spec: MacroSpec { MacroSpec(type: DocumentMacro.self, conformances: []) }
}

enum DocumentMacroError: CustomStringConvertible, Error {
    case onlyApplicableToStruct
    case missingDocumentId
    case parseDocumentIdFailed

    var description: String {
        switch self {
        case .onlyApplicableToStruct: return "@document can only be applied to a struct"
        case .missingDocumentId: return "@document requires a @DocumentId field"
        case .parseDocumentIdFailed: return "@DocumentId field is incorrectly formed"
        }
    }
}

@main
struct CBLMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DocumentMacro.self
    ]
}
